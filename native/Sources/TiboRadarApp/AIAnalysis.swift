import Foundation

struct AIAnalysisEvidence: Codable, Equatable, Sendable {
  let label: String
  let detail: String
  let category: String
  let sourceURL: String?

  enum CodingKeys: String, CodingKey {
    case label, detail, category
    case sourceURL = "source_url"
  }
}

struct AIAnalysis: Codable, Equatable, Sendable {
  let global24h: Int
  let global48h: Int
  let banked24h: Int
  let banked48h: Int
  let affectedUserBanked24h: Int?
  let confidence: String
  let confidenceNote: String
  let likelyWindow: String
  let summary: String
  let evidence: [AIAnalysisEvidence]

  enum CodingKeys: String, CodingKey {
    case global24h = "global_24h"
    case global48h = "global_48h"
    case banked24h = "banked_24h"
    case banked48h = "banked_48h"
    case affectedUserBanked24h = "affected_user_banked_24h"
    case confidence
    case confidenceNote = "confidence_note"
    case likelyWindow = "likely_window"
    case summary, evidence
  }

  func validated() throws -> AIAnalysis {
    let values = [global24h, global48h, banked24h, banked48h]
      + (affectedUserBanked24h.map { [$0] } ?? [])
    guard values.allSatisfy({ (0...100).contains($0) }) else {
      throw AIProviderError.invalidAnalysis("模型返回了 0–100 以外的概率。")
    }
    guard !confidenceNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !likelyWindow.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      throw AIProviderError.invalidAnalysis("模型结果缺少解释或时间窗口。")
    }
    return self
  }

  func snapshot(
    bundle: SourceBundle,
    now: Date = Date()
  ) -> PredictionSnapshot {
    let global48 = max(global24h, global48h)
    let banked48 = max(banked24h, banked48h)
    let combined24 = Self.union(global24h, banked24h)
    let combined48 = max(combined24, Self.union(global48, banked48))
    let level: ProbabilityLevel =
      if combined24 >= 85 {
        .red
      } else if combined24 >= 65 {
        .orange
      } else if combined24 >= 45 {
        .yellow
      } else {
        .green
      }
    let metadata = SourceMetadata(bundle: bundle)
    let stale = !bundle.cacheFallbacks.isEmpty || metadata.isOlderThanFourHours(now: now)
    var mappedEvidence = evidence.prefix(6).map { item in
      Evidence(
        label: item.label,
        detail: item.detail,
        category: Self.normalizedCategory(item.category),
        sourceURL: item.sourceURL.flatMap(URL.init(string:))
      )
    }
    if mappedEvidence.isEmpty {
      mappedEvidence = [
        Evidence(label: "AI 综合判断", detail: summary, category: "context")
      ]
    }

    return PredictionSnapshot(
      generatedAt: now,
      global24h: global24h,
      global48h: global48,
      banked24h: banked24h,
      banked48h: banked48,
      combined24h: combined24,
      combined48h: combined48,
      affectedUserBanked24h: affectedUserBanked24h,
      confidence: Self.normalizedConfidence(confidence),
      confidenceNote: stale ? "部分公开来源来自缓存。\(confidenceNote)" : confidenceNote,
      level: level,
      likelyWindow: likelyWindow,
      lastResetAt: metadata.lastResetAt,
      dataUpdatedAt: metadata.dataUpdatedAt,
      isStale: stale,
      evidence: mappedEvidence,
      latestEvents: metadata.latestEvents,
      sourceErrors: bundle.errors
    )
  }

  private static func union(_ first: Int, _ second: Int) -> Int {
    let value = 1 - (1 - Double(first) / 100) * (1 - Double(second) / 100)
    return max(0, min(100, Int((value * 100).rounded())))
  }

  private static func normalizedConfidence(_ value: String) -> String {
    let lowered = value.lowercased()
    if lowered.contains("high") || value.contains("高") { return "high" }
    if lowered.contains("medium") || lowered.contains("moderate") || value.contains("中") {
      return "medium"
    }
    return "low"
  }

  private static func normalizedCategory(_ value: String) -> String {
    let lowered = value.lowercased()
    if ["positive", "negative", "targeted", "context"].contains(lowered) {
      return lowered
    }
    return "context"
  }
}

struct SourceMetadata: Sendable {
  let lastResetAt: Date?
  let dataUpdatedAt: Date?
  let latestEvents: [RadarEvent]

  init(bundle: SourceBundle) {
    let forecast = bundle.payloads[.forecast]?.objectValue ?? [:]
    lastResetAt = Self.parseDate(forecast.string("last_reset_at"))
    dataUpdatedAt = bundle.payloads.values.compactMap { payload in
      guard let object = payload.objectValue else { return nil }
      return ["updated_at", "fetched_at", "checked_at", "newest_post_at"]
        .compactMap { Self.parseDate(object.string($0)) }
        .max()
    }.max()
    latestEvents = Self.extractEvents(bundle: bundle)
  }

  func isOlderThanFourHours(now: Date) -> Bool {
    dataUpdatedAt.map { now.timeIntervalSince($0) > 4 * 60 * 60 } ?? true
  }

  private static func extractEvents(bundle: SourceBundle) -> [RadarEvent] {
    let timeline = bundle.payloads[.timeline]?.objectValue?.array("events") ?? []
    let feed = bundle.payloads[.feed]?.objectValue?.array("events") ?? []
    var seen = Set<String>()
    return (timeline + feed).compactMap { value -> RadarEvent? in
      guard let event = value.objectValue,
        let id = event.string("id"),
        !id.isEmpty,
        seen.insert(id).inserted
      else { return nil }
      let title = event.string("text") ?? event.string("summary") ?? ""
      guard !title.isEmpty else { return nil }
      let date = ["effective_at", "announced_at", "observed_at", "at", "date"]
        .compactMap { parseDate(event.string($0)) }
        .first
      return RadarEvent(
        id: id,
        kind: event.string("group") ?? event.string("type") ?? event.string("kind") ?? "signal",
        title: title,
        occurredAt: date,
        sourceURL: URL(string: event.string("url") ?? event.string("source_url") ?? ""),
        state: event.string("banked_state") ?? event.string("announcement_state")
      )
    }
    .sorted { ($0.occurredAt ?? .distantPast) > ($1.occurredAt ?? .distantPast) }
    .prefix(5)
    .map { $0 }
  }

  static func parseDate(_ value: String?) -> Date? {
    guard let value, !value.isEmpty else { return nil }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: value) { return date }
    let regular = ISO8601DateFormatter()
    regular.formatOptions = [.withInternetDateTime]
    if let date = regular.date(from: value) { return date }
    if value.count == 10 {
      let formatter = DateFormatter()
      formatter.calendar = Calendar(identifier: .gregorian)
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = TimeZone(secondsFromGMT: 0)
      formatter.dateFormat = "yyyy-MM-dd"
      return formatter.date(from: value)
    }
    return nil
  }
}
