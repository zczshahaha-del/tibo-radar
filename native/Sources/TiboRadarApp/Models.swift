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

  init(
    id: String = UUID().uuidString,
    label: String,
    detail: String,
    category: String = "context",
    delta: Int = 0,
    sourceURL: URL? = nil
  ) {
    self.id = id
    self.label = label
    self.detail = detail
    self.category = category
    self.delta = delta
    self.sourceURL = sourceURL
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

enum SignalStrength: String, Codable, Equatable, Sendable {
  case none
  case weak
  case strong
  case announced

  var label: String {
    switch self {
    case .none: "没有新信号"
    case .weak: "有一点迹象"
    case .strong: "值得关注"
    case .announced: "已有明确预告"
    }
  }

  var action: String {
    switch self {
    case .none: "正常使用"
    case .weak: "先观察"
    case .strong: "可以加速使用"
    case .announced: "尽快使用"
    }
  }

  var rank: Int {
    switch self {
    case .none: 0
    case .weak: 1
    case .strong: 2
    case .announced: 3
    }
  }
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
  let globalSignal: SignalStrength
  let bankedSignal: SignalStrength
  let affectedUserSignal: SignalStrength?
  let analysisNote: String
  let summary: String
  let likelyWindow: String
  let probabilityEstimate: ProbabilityEstimate?
  let probabilityNote: String
  let lastResetAt: Date?
  let dataUpdatedAt: Date?
  let isStale: Bool
  let evidence: [Evidence]
  let latestEvents: [RadarEvent]
  let sourceErrors: [String]

  var overallSignal: SignalStrength {
    [globalSignal, bankedSignal].max { $0.rank < $1.rank } ?? .none
  }
}

extension PredictionSnapshot {
  func markedStale(reason: String) -> PredictionSnapshot {
    PredictionSnapshot(
      generatedAt: generatedAt,
      globalSignal: globalSignal,
      bankedSignal: bankedSignal,
      affectedUserSignal: affectedUserSignal,
      analysisNote: reason,
      summary: summary,
      likelyWindow: likelyWindow,
      probabilityEstimate: nil,
      probabilityNote: "来源已过期，暂不显示估计。",
      lastResetAt: lastResetAt,
      dataUpdatedAt: dataUpdatedAt,
      isStale: true,
      evidence: evidence,
      latestEvents: latestEvents,
      sourceErrors: sourceErrors + [reason]
    )
  }
}
