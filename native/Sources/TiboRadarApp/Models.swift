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

enum ProbabilityLevel: String, Codable, Equatable, Sendable {
  case green
  case yellow
  case orange
  case red

  var label: String {
    switch self {
    case .green: "正常使用"
    case .yellow: "开始关注"
    case .orange: "高关注"
    case .red: "很可能"
    }
  }
}

struct PredictionSnapshot: Codable, Equatable, Sendable {
  let generatedAt: Date
  let global24h: Int
  let global48h: Int
  let banked24h: Int
  let banked48h: Int
  let combined24h: Int
  let combined48h: Int
  let affectedUserBanked24h: Int?
  let confidence: String
  let confidenceNote: String
  let level: ProbabilityLevel
  let likelyWindow: String
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
      confidence: "low",
      confidenceNote: reason,
      level: level,
      likelyWindow: likelyWindow,
      lastResetAt: lastResetAt,
      dataUpdatedAt: dataUpdatedAt,
      isStale: true,
      evidence: evidence,
      latestEvents: latestEvents,
      sourceErrors: sourceErrors + [reason]
    )
  }
}
