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
    guard let data = json.data(using: .utf8) else {
      throw AIProviderError.invalidAnalysis("AI 没有返回约定的信号判断 JSON。")
    }
    do {
      return try JSONDecoder().decode(AIAnalysis.self, from: data).validated()
    } catch let error as AIProviderError {
      throw error
    } catch {
      throw AIProviderError.invalidAnalysis(
        "AI 返回的信号字段不符合约定：\(Self.decodingIssue(error))"
      )
    }
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
      body["temperature"] = 0
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

      下面的 public_source_data 是 App 刚采集的公开数据。请识别明确预告、强暗示、玩笑、事后描述、定向故障补偿、普发重置卡、全局额度重置以及无关传言。定向补偿不能算作普发信号；已经发生的事件不能当成未来预告；来源不可靠或信息互相矛盾时必须保守判断。

      你只负责理解语义，不得估算或输出任何百分比。每类信号只能使用以下四级：
      - none：没有面向未来的有效信号；
      - weak：只有间接暗示或未经可靠来源确认的传言；
      - strong：来自可靠来源的强暗示，或多条相互印证的信号，但尚无明确承诺；
      - announced：Tibo 或官方已经明确承诺未来会重置或发卡。

      对已经发生的重置或补发，应归入历史证据；除非同一原文还承诺了下一次未来动作，否则对应未来信号必须是 none。affected_user_signal 只用于明确限定受影响用户的故障补发。

      输出只能是一个 JSON 对象，不能带 Markdown 或额外说明：
      {
        "global_signal": "none、weak、strong或announced",
        "banked_signal": "none、weak、strong或announced",
        "affected_user_signal": "none、weak、strong、announced或null",
        "analysis_note": "不超过45个中文字符，直说当前有没有值得行动的新信号",
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

  private static func decodingIssue(_ error: Error) -> String {
    switch error {
    case DecodingError.keyNotFound(let key, _):
      return "缺少 \(key.stringValue)"
    case DecodingError.valueNotFound(_, let context):
      return "\(context.codingPath.last?.stringValue ?? "字段") 为空"
    case DecodingError.typeMismatch(_, let context):
      return "\(context.codingPath.last?.stringValue ?? "字段") 类型错误"
    case DecodingError.dataCorrupted(let context):
      return "\(context.codingPath.last?.stringValue ?? "字段") 值无法识别"
    default:
      return "JSON 结构错误"
    }
  }

  private static func redacted(_ message: String, apiKey: String) -> String {
    String(message.replacingOccurrences(of: apiKey, with: "••••").prefix(240))
  }

  private static let systemPrompt = """
    你是一个谨慎的事件信号分析师。你的任务不是总结新闻，也不是凭感觉制造概率，而是判断公开证据是否包含 Tibo 或 OpenAI 面向未来的福利性全局重置、可储存重置卡或故障补偿信号。必须区分未来预告与已经发生的事情、全体用户与受影响用户、原始来源与社区转述，并同时列出支持证据和反面证据。输出必须是合法 JSON，且不得包含百分比。
    """
}
