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
  let global24h: ForecastProbabilityRange
  let global48h: ForecastProbabilityRange
  let banked24h: ForecastProbabilityRange
  let banked48h: ForecastProbabilityRange
  let combined24h: ForecastProbabilityRange
  let combined48h: ForecastProbabilityRange
  let affectedUserBanked24h: ForecastProbabilityRange?
  let usageAdvice: UsageAdvice
  let analysisNote: String
  let conditionalWindow: String
  let summary: String
  let evidence: [AIAnalysisEvidence]

  enum CodingKeys: String, CodingKey {
    case global24h = "global_24h"
    case global48h = "global_48h"
    case banked24h = "banked_24h"
    case banked48h = "banked_48h"
    case combined24h = "combined_24h"
    case combined48h = "combined_48h"
    case affectedUserBanked24h = "affected_user_banked_24h"
    case usageAdvice = "usage_advice"
    case analysisNote = "analysis_note"
    case conditionalWindow = "conditional_window"
    case summary, evidence
  }

  func validated() throws -> AIAnalysis {
    guard !analysisNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !conditionalWindow.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      throw AIProviderError.invalidAnalysis("模型结果缺少判断原因或时间窗口。")
    }
    let requiredRanges = [
      ("global_24h", global24h),
      ("global_48h", global48h),
      ("banked_24h", banked24h),
      ("banked_48h", banked48h),
      ("combined_24h", combined24h),
      ("combined_48h", combined48h),
    ]
    for (name, range) in requiredRanges {
      try Self.validate(range, name: name, lowerBound: 1, upperBound: 99)
    }
    if let affectedUserBanked24h {
      try Self.validate(
        affectedUserBanked24h,
        name: "affected_user_banked_24h",
        lowerBound: 0,
        upperBound: 100
      )
    }
    try Self.validateCumulative(global24h, global48h, name: "global")
    try Self.validateCumulative(banked24h, banked48h, name: "banked")
    try Self.validateCumulative(combined24h, combined48h, name: "combined")
    try Self.validateCombined(combined24h, global24h, banked24h, name: "combined_24h")
    try Self.validateCombined(combined48h, global48h, banked48h, name: "combined_48h")
    let userFacingText = [analysisNote, conditionalWindow, summary]
      + evidence.flatMap { [$0.label, $0.detail] }
    guard !userFacingText.contains(where: Self.containsPercentage) else {
      throw AIProviderError.invalidAnalysis("AI 返回了未经校准的百分比，已拒绝显示。")
    }
    return self
  }

  func snapshot(
    bundle: SourceBundle,
    now: Date = Date()
  ) -> PredictionSnapshot {
    let metadata = SourceMetadata(bundle: bundle)
    let stale = !bundle.cacheFallbacks.isEmpty || metadata.isOlderThanFourHours(now: now)
    let calibration = ProbabilityCalibration.evaluate(bundle: bundle)
    let sourceIndex = EvidenceSourceIndex(bundle: bundle)
    var mappedEvidence = evidence.prefix(6).enumerated().map { index, item in
      let sourceURL = item.sourceURL.flatMap(URL.init(string:))
      return (
        originalIndex: index,
        evidence: Evidence(
          label: item.label,
          detail: item.detail,
          category: Self.normalizedCategory(item.category),
          sourceURL: sourceURL,
          sourceDate: sourceIndex.date(for: sourceURL)
        )
      )
    }
    .sorted { left, right in
      switch (left.evidence.sourceDate, right.evidence.sourceDate) {
      case let (leftDate?, rightDate?) where leftDate != rightDate:
        return leftDate > rightDate
      case (_?, nil):
        return true
      case (nil, _?):
        return false
      default:
        return left.originalIndex < right.originalIndex
      }
    }
    .map(\.evidence)
    if mappedEvidence.isEmpty {
      mappedEvidence = [
        Evidence(label: "AI 综合判断", detail: summary, category: "context")
      ]
    }

    return PredictionSnapshot(
      generatedAt: now,
      global24h: global24h,
      global48h: global48h,
      banked24h: banked24h,
      banked48h: banked48h,
      combined24h: combined24h,
      combined48h: combined48h,
      affectedUserBanked24h: affectedUserBanked24h,
      usageAdvice: usageAdvice,
      analysisNote: stale ? "部分公开来源来自缓存。\(analysisNote)" : analysisNote,
      summary: summary,
      conditionalWindow: conditionalWindow,
      historicalBaseline: calibration.estimate,
      baselineNote: Self.baselineNote(calibration, stale: stale),
      lastResetAt: metadata.lastResetAt,
      dataUpdatedAt: metadata.dataUpdatedAt,
      isStale: stale,
      evidence: mappedEvidence,
      latestEvents: metadata.latestEvents,
      sourceErrors: bundle.errors
    )
  }

  private static func normalizedCategory(_ value: String) -> String {
    let lowered = value.lowercased()
    if ["positive", "negative", "targeted", "context"].contains(lowered) {
      return lowered
    }
    return "context"
  }

  private static func containsPercentage(_ value: String) -> Bool {
    value.contains("%") || value.contains("％") || value.contains("百分之")
  }

  private static func validate(
    _ range: ForecastProbabilityRange,
    name: String,
    lowerBound: Int,
    upperBound: Int
  ) throws {
    guard (lowerBound...upperBound).contains(range.lower),
      (lowerBound...upperBound).contains(range.likely),
      (lowerBound...upperBound).contains(range.upper),
      range.lower <= range.likely,
      range.likely <= range.upper
    else {
      throw AIProviderError.invalidAnalysis("AI 返回的 \(name) 概率范围无效。")
    }
  }

  private static func validateCumulative(
    _ first24h: ForecastProbabilityRange,
    _ first48h: ForecastProbabilityRange,
    name: String
  ) throws {
    guard first48h.lower >= first24h.lower,
      first48h.likely >= first24h.likely,
      first48h.upper >= first24h.upper
    else {
      throw AIProviderError.invalidAnalysis("AI 返回的 \(name) 48 小时概率低于 24 小时。")
    }
  }

  private static func validateCombined(
    _ combined: ForecastProbabilityRange,
    _ global: ForecastProbabilityRange,
    _ banked: ForecastProbabilityRange,
    name: String
  ) throws {
    guard combined.lower >= max(global.lower, banked.lower),
      combined.likely >= max(global.likely, banked.likely),
      combined.upper >= max(global.upper, banked.upper)
    else {
      throw AIProviderError.invalidAnalysis("AI 返回的 \(name) 综合概率低于分类概率。")
    }
  }

  private static func baselineNote(
    _ calibration: ProbabilityCalibrationResult,
    stale: Bool
  ) -> String {
    let freshness = stale ? "公开来源部分过期。" : ""
    guard let estimate = calibration.estimate else {
      return freshness + calibration.note
    }
    return freshness
      + "历史基准（\(estimate.sampleSize) 次回放）：24 小时 \(estimate.label24h)，"
      + "48 小时 \(estimate.label48h)。"
  }
}

private struct EvidenceSourceIndex {
  private var datesByURL: [String: Date] = [:]
  private var datesByID: [String: Date] = [:]

  init(bundle: SourceBundle) {
    for payload in bundle.payloads.values {
      index(payload)
    }
  }

  func date(for sourceURL: URL?) -> Date? {
    guard let sourceURL else { return nil }
    if let exact = datesByURL[Self.normalized(sourceURL.absoluteString)] {
      return exact
    }
    return datesByID[sourceURL.lastPathComponent]
  }

  private mutating func index(_ value: JSONValue) {
    switch value {
    case .object(let object):
      index(object)
      for child in object.values {
        index(child)
      }
    case .array(let values):
      for child in values {
        index(child)
      }
    case .string, .number, .bool, .null:
      break
    }
  }

  private mutating func index(_ object: [String: JSONValue]) {
    let sourceDate = [
      "at", "declared_at", "announced_at", "observed_at", "effective_at",
      "started_at", "created_at", "date",
    ]
    .compactMap { SourceMetadata.parseDate(object.string($0)) }
    .first
    guard let sourceDate else { return }

    for key in ["url", "source_url", "shortlink"] {
      guard let rawURL = object.string(key), !rawURL.isEmpty else { continue }
      Self.register(sourceDate, in: &datesByURL, key: Self.normalized(rawURL))
    }
    if let id = object.string("id"), !id.isEmpty {
      Self.register(sourceDate, in: &datesByID, key: id)
    }
  }

  private static func register(_ date: Date, in index: inout [String: Date], key: String) {
    guard !key.isEmpty else { return }
    if let existing = index[key], existing >= date { return }
    index[key] = date
  }

  private static func normalized(_ rawURL: String) -> String {
    rawURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
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
