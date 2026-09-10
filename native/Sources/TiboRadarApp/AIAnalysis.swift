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
  let globalSignal: SignalStrength
  let bankedSignal: SignalStrength
  let affectedUserSignal: SignalStrength?
  let analysisNote: String
  let likelyWindow: String
  let summary: String
  let evidence: [AIAnalysisEvidence]

  enum CodingKeys: String, CodingKey {
    case globalSignal = "global_signal"
    case bankedSignal = "banked_signal"
    case affectedUserSignal = "affected_user_signal"
    case analysisNote = "analysis_note"
    case likelyWindow = "likely_window"
    case summary, evidence
  }

  func validated() throws -> AIAnalysis {
    guard !analysisNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !likelyWindow.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      throw AIProviderError.invalidAnalysis("模型结果缺少判断原因或时间窗口。")
    }
    let userFacingText = [analysisNote, likelyWindow, summary]
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
      globalSignal: globalSignal,
      bankedSignal: bankedSignal,
      affectedUserSignal: affectedUserSignal,
      analysisNote: stale ? "部分公开来源来自缓存。\(analysisNote)" : analysisNote,
      summary: summary,
      likelyWindow: likelyWindow,
      probabilityEstimate: stale ? nil : calibration.estimate,
      probabilityNote: stale ? "来源已过期，暂不显示估计。" : calibration.note,
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
