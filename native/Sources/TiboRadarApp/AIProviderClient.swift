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
      throw AIProviderError.invalidAnalysis("AI 没有返回约定的概率预测 JSON。")
    }
    do {
      return try JSONDecoder().decode(AIAnalysis.self, from: data).validated()
    } catch let error as AIProviderError {
      throw error
    } catch {
      throw AIProviderError.invalidAnalysis(
        "AI 返回的预测字段不符合约定：\(Self.decodingIssue(error))"
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

      下面的 public_source_data 是 App 刚采集的公开数据。historical_baseline 中包含按过去时间窗回放得到的历史概率范围，它是预测起点，不是最终答案。请再结合 Tibo 与官方近期原文、联网资料、历史节奏、没有出现新言论这一事实、反面证据和来源新鲜度，给出你对未来事件的综合概率预测。

      recent_tibo_posts.text 是近期 Tibo 帖子或回复的正文，closing_paragraph 是为防止长帖遗漏而单独保留的最后一段；recent_tibo_feed 中的 summary 可能只截取开头。判断时必须阅读全文和 closing_paragraph，尤其检查末尾是否有重置承诺、目标人群和截止时间；摘要与正文不完整或冲突时，以 recent_tibo_posts.text 为准。输入里不会提供上游关键词分类结论，你必须自己根据原文判断。所有 at 原始时间均为 UTC，published_at_beijing 和 published_at_pacific 是同一时刻的两种本地表示；America/Los_Angeles 只是作者可能所在时区的工作假设，不是已确认事实。遇到 today、tonight、Tuesday、3am、midnight、end of day 等相对日期或时刻，必须比较发帖当时的北京时间与可能的作者当地日期，不能直接套用查看者日期；无法确定作者时区时扩大时间不确定性，但不能把未来时刻误判成已经过去。英文 “is landing by ...” 表示尚在到达过程并承诺最晚时间，不等于已经完成的 “landed”。

      对 is_reply=true 的内容，必须把 reply_context.parent、reply_context.quoted_post 与 Tibo 回复合起来理解。父帖明确索要 banked reset，而 Tibo 用同意语气回应时，应上调普发重置卡概率，但不能因此上调全局重置概率。父帖或引用帖谈论产品发布时，单独一次 Tuesday 不足以确认重置发放时间；但这不是忽略后续线索的硬规则。若此前在明确索要 banked reset 的对话中同时出现 Tuesday，之后 Tibo 又在另一条新动态中重复 Tuesday 或给出 3am 等更具体时刻，必须把这种跨帖重复视为对普发重置卡的追加正面信号，并结合作者可能仍处于前一自然日来判断未来 24/48 小时窗口；没有全局重置表述时仍不得据此上调全局重置。若 reply_context_status=missing，不得仅凭 okay、it、this 猜测指代，但仍要与其他独立新动态的重复日期或时刻交叉判断。

      recent_tibo_context 是 Tibo 最新公开动态，visibility_only 只是上游展示分类，不代表语义上一定与重置无关。普通闲聊本身不得作为正面信号，但若其中的日期、星期或时刻与 recent_tibo_posts 中已有重置对话重复，必须做跨帖关联，不能概括成“均为普通互动”。tibo_feed_freshness 用来判断数据是否真正更新；不要把某条旧的重置相关言论误写成“最新消息”。

      官方原帖若明确承诺在未来 24/48 小时内向广泛用户发放重置或重置卡，这条直接证据应优先于历史间隔。刚发生过重置可以作为反面证据，但不能把尚未到期的明确承诺压回普通历史基准。仍要区分全局福利、普发重置卡和仅限受影响用户的定向补偿。

      你必须每次都预测，不能用“没有新信号”代替概率，也不能因为没有新信号就返回全零。没有新信号时，概率应保留在合理的历史基准附近；明确预告、强暗示或反面证据可以改变范围，但必须在 analysis_note 里直说原因。

      每个概率使用 lower、likely、upper 三个整数表达范围。全局重置、普发重置卡和两者至少发生一种的 24/48 小时范围都必须为 1–99，且 lower ≤ likely ≤ upper。48 小时累计概率不能低于对应的 24 小时概率；combined 必须不低于 global 和 banked。定向故障补发只针对受影响用户，不得混入 combined；没有对应人群时返回 null。

      已经发生的重置只能作为历史，不得冒充未来事件。文字说明中不要重复百分比，数字只放在结构化范围字段里。

      evidence 数组必须按原始来源时间从新到旧排列；较旧的历史背景放在较新证据之后。能找到原始来源时必须填写 source_url。最近 72 小时若出现与已有重置信号重复的日期、星期或具体时刻，必须把最新原文单列为 evidence，标题或说明中保留原词（例如 “3am on a tuesday”），不得用“近期均为普通互动”把它合并掉。

      输出只能是一个 JSON 对象，不能带 Markdown 或额外说明：
      {
        "global_24h": {"lower": 1到99整数, "likely": 1到99整数, "upper": 1到99整数},
        "global_48h": {"lower": 1到99整数, "likely": 1到99整数, "upper": 1到99整数},
        "banked_24h": {"lower": 1到99整数, "likely": 1到99整数, "upper": 1到99整数},
        "banked_48h": {"lower": 1到99整数, "likely": 1到99整数, "upper": 1到99整数},
        "combined_24h": {"lower": 1到99整数, "likely": 1到99整数, "upper": 1到99整数},
        "combined_48h": {"lower": 1到99整数, "likely": 1到99整数, "upper": 1到99整数},
        "affected_user_banked_24h": {"lower": 0到100整数, "likely": 0到100整数, "upper": 0到100整数}或null,
        "usage_advice": "normal、watch、accelerate或use_now",
        "analysis_note": "不超过55个中文字符，解释历史基准和近期证据怎样形成当前范围，不写百分比",
        "conditional_window": "假设事件会在未来24小时发生，它相对更可能集中在哪个北京时间窗口；只写如9月11日 08:00–12:00，不得早于current_time；没有明显集中时段写暂无集中时段",
        "summary": "一句话预测结论，不重复数字",
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
      let detail = String(context.debugDescription.prefix(120))
      return "\(context.codingPath.last?.stringValue ?? "字段") 值无法识别：\(detail)"
    default:
      return "JSON 结构错误"
    }
  }

  private static func redacted(_ message: String, apiKey: String) -> String {
    String(message.replacingOccurrences(of: apiKey, with: "••••").prefix(240))
  }

  private static let systemPrompt = """
    你是一个谨慎的概率预测分析师。你的任务是根据历史基准和最新公开证据，预测 Tibo 或 OpenAI 在未来 24/48 小时向 Codex 用户发放福利性全局重置、可储存重置卡或故障补偿的概率范围。没有新信号也必须预测，因为突发事件仍有历史基础概率。必须区分未来预告与已经发生的事情、全体用户与受影响用户、原始来源与社区转述，并同时列出支持证据和反面证据。输出必须是合法 JSON。
    """
}
