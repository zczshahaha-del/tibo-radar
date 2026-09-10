import Foundation

enum AIProviderError: LocalizedError, Equatable {
  case missingKey
  case unauthorized
  case rateLimited
  case server(status: Int, message: String)
  case invalidResponse
  case invalidAnalysis(String)

  var errorDescription: String? {
    switch self {
    case .missingKey:
      "还没有保存 API Key，请先打开设置。"
    case .unauthorized:
      "API Key 无效，或 Key 与服务地域不匹配。"
    case .rateLimited:
      "模型服务正在限流或账户余额不足，请稍后重试。"
    case .server(let status, let message):
      "模型服务返回错误（HTTP \(status)）：\(message)"
    case .invalidResponse:
      "模型返回了无法识别的响应。"
    case .invalidAnalysis(let message):
      message
    }
  }
}

protocol AIAnalyzing: Sendable {
  func analyze(
    context: String,
    configuration: AIConfiguration,
    apiKey: String
  ) async throws -> AIAnalysis

  func testConnection(
    configuration: AIConfiguration,
    apiKey: String
  ) async throws
}

final class AIProviderClient: AIAnalyzing, @unchecked Sendable {
  private let session: URLSession

  init(session: URLSession = .shared) {
    self.session = session
  }

  func analyze(
    context: String,
    configuration: AIConfiguration,
    apiKey: String
  ) async throws -> AIAnalysis {
    let prompt = userPrompt(context: context, provider: configuration.provider)
    let body = requestBody(
      configuration: configuration,
      userContent: prompt,
      isConnectionTest: false
    )
    let content = try await perform(
      body: body,
      configuration: configuration,
      apiKey: apiKey
    )
    let json = extractJSONObject(from: content)
    guard let data = json.data(using: .utf8),
      let analysis = try? JSONDecoder().decode(AIAnalysis.self, from: data)
    else {
      throw AIProviderError.invalidAnalysis("AI 没有返回约定的预测 JSON。")
    }
    return try analysis.validated()
  }

  func testConnection(
    configuration: AIConfiguration,
    apiKey: String
  ) async throws {
    let body = requestBody(
      configuration: configuration,
      userContent: "只回复 OK，用于验证 API 连接。",
      isConnectionTest: true
    )
    let content = try await perform(
      body: body,
      configuration: configuration,
      apiKey: apiKey
    )
    guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw AIProviderError.invalidResponse
    }
  }

  private func perform(
    body: [String: Any],
    configuration: AIConfiguration,
    apiKey: String
  ) async throws -> String {
    let cleanedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanedKey.isEmpty else { throw AIProviderError.missingKey }

    var request = URLRequest(url: configuration.provider.endpoint)
    request.httpMethod = "POST"
    request.timeoutInterval = 75
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(cleanedKey)", forHTTPHeaderField: "Authorization")
    request.setValue("TiboRadar/0.3", forHTTPHeaderField: "User-Agent")
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw AIProviderError.invalidResponse
    }
    guard (200...299).contains(http.statusCode) else {
      let message = Self.safeErrorMessage(from: data, redacting: cleanedKey)
      switch http.statusCode {
      case 401, 403: throw AIProviderError.unauthorized
      case 402, 429: throw AIProviderError.rateLimited
      default: throw AIProviderError.server(status: http.statusCode, message: message)
      }
    }

    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let choices = root["choices"] as? [[String: Any]],
      let message = choices.first?["message"] as? [String: Any],
      let content = message["content"] as? String
    else {
      throw AIProviderError.invalidResponse
    }
    return content
  }

  private func requestBody(
    configuration: AIConfiguration,
    userContent: String,
    isConnectionTest: Bool
  ) -> [String: Any] {
    var body: [String: Any] = [
      "model": configuration.model,
      "messages": [
        ["role": "system", "content": isConnectionTest ? "你是连接测试助手。" : Self.systemPrompt],
        ["role": "user", "content": userContent],
      ],
      "stream": false,
    ]
    if !isConnectionTest {
      body["response_format"] = ["type": "json_object"]
    }
    if configuration.provider == .qwen {
      body["enable_search"] = !isConnectionTest
      if !isConnectionTest {
        body["search_options"] = ["search_strategy": "turbo", "enable_source": true]
      }
    } else if !isConnectionTest {
      body["thinking"] = ["type": "enabled"]
      body["reasoning_effort"] = "high"
    }
    return body
  }

  private func userPrompt(context: String, provider: AIProvider) -> String {
    let searchInstruction =
      provider == .qwen
      ? "请同时联网搜索最近 72 小时内 Tibo、OpenAI/Codex 团队以及社区关于 Codex reset、banked reset、reset credit、充值卡或补偿的最新公开言论，并优先采用原始来源。"
      : "你不能假装做过额外联网搜索；请只根据下面由 App 实时联网采集的公开原文判断。"
    return """
      \(searchInstruction)

      下面的 public_source_data 是 App 刚采集的公开数据。请识别明确预告、强暗示、玩笑、事后描述、定向故障补偿、普发重置卡、全局额度重置以及无关传言。定向补偿不能提高普发概率；已经发生的事件不能当成未来预告；来源不可靠或信息互相矛盾时必须降低置信度。

      输出只能是一个 JSON 对象，不能带 Markdown 或额外说明：
      {
        "global_24h": 0到100整数,
        "global_48h": 0到100整数,
        "banked_24h": 0到100整数,
        "banked_48h": 0到100整数,
        "affected_user_banked_24h": 0到100整数或null,
        "confidence": "low或medium或high",
        "confidence_note": "不超过45个中文字符，直说为什么可靠或不可靠",
        "likely_window": "只写简短北京时间，如9月11日 08:00–12:00；没有可靠时间必须写暂无可靠时间",
        "summary": "一句话综合判断",
        "evidence": [
          {
            "label": "简短标题",
            "detail": "解释这条证据怎样影响判断",
            "category": "positive、negative、targeted或context",
            "source_url": "可核对的原始链接或null"
          }
        ]
      }

      public_source_data:
      \(context)
      """
  }

  private func extractJSONObject(from content: String) -> String {
    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let first = trimmed.firstIndex(of: "{"),
      let last = trimmed.lastIndex(of: "}"),
      first <= last
    else { return trimmed }
    return String(trimmed[first...last])
  }

  private static func safeErrorMessage(from data: Data, redacting apiKey: String) -> String {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return "请求失败" }
    if let error = root["error"] as? [String: Any],
      let message = error["message"] as? String
    {
      return redacted(message, apiKey: apiKey)
    }
    if let message = root["message"] as? String {
      return redacted(message, apiKey: apiKey)
    }
    return "请求失败"
  }

  private static func redacted(_ message: String, apiKey: String) -> String {
    String(message.replacingOccurrences(of: apiKey, with: "••••").prefix(240))
  }

  private static let systemPrompt = """
    你是一个谨慎的事件预测分析师。你的任务不是总结新闻，而是根据公开证据估算 Tibo 或 OpenAI 在未来 24/48 小时向 Codex 用户发放福利性全局重置、可储存重置卡或故障补偿的概率。概率是有不确定性的判断，不能把猜测说成官方承诺。必须区分未来预告与已经发生的事情、全体用户与受影响用户、原始来源与社区转述，并同时列出支持证据和反面证据。输出必须是合法 JSON。
    """
}
