import Foundation

enum RadarSource: String, CaseIterable, Codable, Sendable {
  case forecast
  case timeline
  case feed
  case status
  case openAIStatus = "openai_status"

  var url: URL {
    switch self {
    case .forecast: URL(string: "https://codex-reset.com/api/forecast")!
    case .timeline: URL(string: "https://codex-reset.com/api/timeline")!
    case .feed: URL(string: "https://codex-reset.com/api/feed")!
    case .status: URL(string: "https://codex-reset.com/api/status-history")!
    case .openAIStatus: URL(string: "https://status.openai.com/api/v2/incidents.json")!
    }
  }
}

struct SourceBundle: Sendable {
  var payloads: [RadarSource: JSONValue]
  var cacheFallbacks: Set<RadarSource>
  var errors: [String]
}

struct Evidence: Identifiable, Codable, Equatable, Sendable {
  let id: String
  let label: String
  let detail: String
  let category: String
  let delta: Int
  let sourceURL: URL?
  let sourceDate: Date?

  init(
    id: String = UUID().uuidString,
    label: String,
    detail: String,
    category: String = "context",
    delta: Int = 0,
    sourceURL: URL? = nil,
    sourceDate: Date? = nil
  ) {
    self.id = id
    self.label = label
    self.detail = detail
    self.category = category
    self.delta = delta
    self.sourceURL = sourceURL
    self.sourceDate = sourceDate
  }
}

struct RadarEvent: Identifiable, Codable, Equatable, Sendable {
  let id: String
  let kind: String
  let title: String
  let occurredAt: Date?
  let sourceURL: URL?
  let state: String?
}

enum UsageAdvice: String, Codable, Equatable, Sendable {
  case normal
  case watch
  case accelerate
  case useNow = "use_now"

  var label: String {
    switch self {
    case .normal: "正常使用"
    case .watch: "开始关注"
    case .accelerate: "可以加速使用"
    case .useNow: "尽快使用"
    }
  }
}

struct ForecastProbabilityRange: Codable, Equatable, Sendable {
  let lower: Int
  let likely: Int
  let upper: Int

  var label: String { "\(lower)–\(upper)%" }
}

enum ProbabilityQuality: String, Codable, Equatable, Sendable {
  case historicalEstimate
  case calibrated

  var label: String {
    switch self {
    case .historicalEstimate: "历史估计"
    case .calibrated: "已校准"
    }
  }
}

struct ProbabilityEstimate: Codable, Equatable, Sendable {
  let lower24h: Int
  let upper24h: Int
  let lower48h: Int
  let upper48h: Int
  let sampleSize: Int
  let brierScore: Double
  let quality: ProbabilityQuality

  var label24h: String { "\(lower24h)–\(upper24h)%" }
  var label48h: String { "\(lower48h)–\(upper48h)%" }
}

struct PredictionSnapshot: Codable, Equatable, Sendable {
  let generatedAt: Date
  let global24h: ForecastProbabilityRange
  let global48h: ForecastProbabilityRange
  let banked24h: ForecastProbabilityRange
  let banked48h: ForecastProbabilityRange
  let combined24h: ForecastProbabilityRange
  let combined48h: ForecastProbabilityRange
  let affectedUserBanked24h: ForecastProbabilityRange?
  let usageAdvice: UsageAdvice
  let analysisNote: String
  let summary: String
  let conditionalWindow: String
  let historicalBaseline: ProbabilityEstimate?
  let baselineNote: String
  let lastResetAt: Date?
  let dataUpdatedAt: Date?
  let isStale: Bool
  let evidence: [Evidence]
  let latestEvents: [RadarEvent]
  let sourceErrors: [String]

}

extension PredictionSnapshot {
  func markedStale(reason: String) -> PredictionSnapshot {
    PredictionSnapshot(
      generatedAt: generatedAt,
      global24h: global24h,
      global48h: global48h,
      banked24h: banked24h,
      banked48h: banked48h,
      combined24h: combined24h,
      combined48h: combined48h,
      affectedUserBanked24h: affectedUserBanked24h,
      usageAdvice: usageAdvice,
      analysisNote: reason,
      summary: summary,
      conditionalWindow: conditionalWindow,
      historicalBaseline: historicalBaseline,
      baselineNote: "来源已过期，当前显示上次 AI 预测。",
      lastResetAt: lastResetAt,
      dataUpdatedAt: dataUpdatedAt,
      isStale: true,
      evidence: evidence,
      latestEvents: latestEvents,
      sourceErrors: sourceErrors + [reason]
    )
  }
}
