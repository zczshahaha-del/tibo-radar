import Foundation

struct Predictor: Sendable {
  private let directFutureTerms = [
    " will ", "tomorrow", "later today", "next hour", "within an hour",
    "within a hour", "lands at", "lands around", "lands by", "soon",
  ]
  private let resetTerms = ["reset", "resetting", "banked reset"]
  private let globalTerms = [
    "all paid", "all users", "everyone", "every codex", "global",
  ]
  private let targetedTerms = [
    "affected", "eligible", "some users", "some plus", "who used one",
    "without access", "affected time window",
  ]
  private let teaserTerms = [
    "hold on to your codex", "burn as much usage", "burn usage",
    "you know what's coming", "who says it won't reset", "new milestone",
  ]
  private let completedTerms = [
    "all reset", "have reset", "has been reset", "reset propagated",
    "it is done", "reset for everyone",
  ]

  func predict(bundle: SourceBundle, now: Date = Date()) -> PredictionSnapshot {
    let forecast = bundle.payloads[.forecast]?.objectValue ?? [:]
    let timeline = bundle.payloads[.timeline]?.objectValue ?? [:]
    let feed = bundle.payloads[.feed]?.objectValue ?? [:]
    let status = bundle.payloads[.status]?.objectValue ?? [:]
    let openAIStatus = bundle.payloads[.openAIStatus]?.objectValue ?? [:]
    let events = mergedEvents(timeline: timeline, feed: feed)

    let probabilities = forecast.object("probabilities") ?? [:]
    var global24 = probabilities.number("rounded_24h") ?? 24
    var global48 = probabilities.number("rounded_48h") ?? 43
    var banked24 = 8.0
    var banked48 = 15.0
    var affectedUserBanked: Int?
    var evidence: [Evidence] = []

    let cadence = forecast.object("cadence") ?? [:]
    if let medianDays = cadence.number("recent_median_days"),
      let ageDays = forecast.number("age_days")
    {
      evidence.append(
        Evidence(
          id: "cadence",
          label: "历史节奏",
          detail: String(
            format: "距上次重置 %.1f 天；近期典型间隔 %.1f 天。",
            ageDays,
            medianDays
          ),
          category: "baseline",
          sourceURL: URL(string: "https://codex-reset.com/timeline")
        ))
    }

    let lastReset = parseDate(forecast.string("last_reset_at"))
    if let lastReset, now.timeIntervalSince(lastReset) < 24 * 60 * 60 {
      global24 -= 8
      global48 -= 4
      evidence.append(
        Evidence(
          id: "cooldown",
          label: "重置冷却",
          detail: "上次全局重置不足 24 小时。",
          category: "negative",
          delta: -8
        ))
    }

    let postResetEvents =
      events
      .filter { event in
        guard let date = eventDate(event) else { return false }
        return lastReset.map { date > $0 } ?? true
      }
      .sorted { (eventDate($0) ?? .distantPast) > (eventDate($1) ?? .distantPast) }

    var explicitFuture: [String: JSONValue]?
    var strongTeaser: [String: JSONValue]?
    var latestBanked: [String: JSONValue]?

    for event in postResetEvents {
      let text = eventText(event)
      let kind = eventKind(event)
      if ["credits", "banked"].contains(kind), latestBanked == nil {
        latestBanked = event
      }
      if kind == "reset",
        containsAny(text, resetTerms),
        containsAny(" \(text) ", directFutureTerms),
        !containsAny(text, completedTerms),
        explicitFuture == nil
      {
        explicitFuture = event
      } else if containsAny(text, teaserTerms), strongTeaser == nil {
        strongTeaser = event
      }
    }

    if let event = explicitFuture {
      let text = eventText(event)
      let floor = containsAny(text, globalTerms) ? 88 : 72
      global24 = max(global24, Double(floor))
      global48 = max(global48, Double(min(96, floor + 7)))
      evidence.append(
        Evidence(
          id: "explicit-future",
          label: "Tibo 明确预告",
          detail: clipped(text),
          category: "positive",
          delta: floor,
          sourceURL: eventURL(event)
        ))
    } else if let event = strongTeaser {
      global24 += 18
      global48 += 12
      evidence.append(
        Evidence(
          id: "strong-teaser",
          label: "Tibo 强暗示",
          detail: clipped(eventText(event)),
          category: "positive",
          delta: 18,
          sourceURL: eventURL(event)
        ))
    }

    if let event = latestBanked {
      let text = eventText(event)
      let recent = eventDate(event).map { now.timeIntervalSince($0) <= 48 * 60 * 60 } ?? false
      let targeted = containsAny(text, targetedTerms)
      let broad = containsAny(text, globalTerms) && !targeted
      let state = event.string("banked_state") ?? ""

      if recent, targeted {
        affectedUserBanked = 94
        evidence.append(
          Evidence(
            id: "targeted-compensation",
            label: "定向补发",
            detail: "Tibo 已承诺补发给故障时段内受影响的用户；这不会提高普发概率。",
            category: "targeted",
            sourceURL: eventURL(event)
          ))
      } else if recent, broad, ["announced", "arriving"].contains(state) {
        banked24 = max(banked24, 94)
        banked48 = max(banked48, 98)
        evidence.append(
          Evidence(
            id: "banked-announced",
            label: "重置卡已预告",
            detail: clipped(text),
            category: "positive",
            delta: 86,
            sourceURL: eventURL(event)
          ))
      } else if recent, broad {
        banked24 = max(banked24, 72)
        banked48 = max(banked48, 84)
      }
    }

    if let incident = recentIncident(
      openAIStatus: openAIStatus,
      fallbackStatus: status,
      now: now
    ) {
      let incidentStatus = incident.string("status") ?? ""
      let active = !["resolved", "postmortem", "completed"].contains(incidentStatus)
      let delta = active ? 12 : 5
      global24 += Double(delta)
      global48 += Double(max(3, delta - 4))
      evidence.append(
        Evidence(
          id: "recent-incident",
          label: "Codex 状态事件",
          detail: incident.string("name") ?? "近期 Codex 服务异常",
          category: active ? "positive" : "context",
          delta: delta,
          sourceURL: URL(
            string: incident.string("shortlink") ?? incident.string("source_url") ?? "")
        ))
    }

    let global24Value = clamp(global24)
    let global48Value = max(global24Value, clamp(global48))
    let banked24Value = clamp(banked24)
    let banked48Value = max(banked24Value, clamp(banked48))
    let combined24 = union(global24Value, banked24Value)
    let combined48 = max(combined24, union(global48Value, banked48Value))

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

    let dataUpdatedAt = freshnessDate(in: bundle.payloads.values)
    let isStale =
      !bundle.cacheFallbacks.isEmpty
      || dataUpdatedAt.map { now.timeIntervalSince($0) > 4 * 60 * 60 } == true

    var confidence = forecast.string("confidence") ?? "low"
    if explicitFuture != nil || banked24Value >= 90 {
      confidence = "high"
    } else if isStale {
      confidence = "low"
    }
    let sourceNote =
      forecast.string("confidence_note")
      ?? "历史样本较少，概率只用于安排用量。"

    return PredictionSnapshot(
      generatedAt: now,
      global24h: global24Value,
      global48h: global48Value,
      banked24h: banked24Value,
      banked48h: banked48Value,
      combined24h: combined24,
      combined48h: combined48,
      affectedUserBanked24h: affectedUserBanked,
      confidence: confidence,
      confidenceNote: isStale ? "部分数据来自缓存；请把当前概率视为低置信度。" : sourceNote,
      level: level,
      likelyWindow: likelyWindow(forecast),
      lastResetAt: lastReset,
      dataUpdatedAt: dataUpdatedAt,
      isStale: isStale,
      evidence: Array(evidence.prefix(6)),
      latestEvents: latestEvents(events),
      sourceErrors: bundle.errors
    )
  }

  private func mergedEvents(
    timeline: [String: JSONValue],
    feed: [String: JSONValue]
  ) -> [[String: JSONValue]] {
    let raw = (timeline.array("events") ?? []) + (feed.array("events") ?? [])
    var seen = Set<String>()
    var merged: [[String: JSONValue]] = []
    for value in raw {
      guard let event = value.objectValue else { continue }
      let id = event.string("id") ?? ""
      guard !id.isEmpty, seen.insert(id).inserted else { continue }
      merged.append(event)
    }
    return merged
  }

  private func latestEvents(_ events: [[String: JSONValue]]) -> [RadarEvent] {
    events
      .sorted { (eventDate($0) ?? .distantPast) > (eventDate($1) ?? .distantPast) }
      .compactMap { event -> RadarEvent? in
        guard let id = event.string("id"), !id.isEmpty else { return nil }
        let title = eventText(event).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        return RadarEvent(
          id: id,
          kind: eventKind(event),
          title: title,
          occurredAt: eventDate(event),
          sourceURL: eventURL(event),
          state: event.string("banked_state") ?? event.string("announcement_state")
        )
      }
      .prefix(5)
      .map { $0 }
  }

  private func recentIncident(
    openAIStatus: [String: JSONValue],
    fallbackStatus: [String: JSONValue],
    now: Date
  ) -> [String: JSONValue]? {
    let values =
      (openAIStatus.array("incidents") ?? [])
      + (fallbackStatus.array("incidents") ?? [])
    var seen = Set<String>()
    var candidates: [(Date, [String: JSONValue])] = []

    for value in values {
      guard let incident = value.objectValue else { continue }
      let id = incident.string("id") ?? ""
      guard seen.insert(id).inserted else { continue }
      let searchable = "\(incident.string("name") ?? "") \(incident.string("body") ?? "")"
        .lowercased()
      let related =
        incident.bool("codex_related") == true
        || ["codex", "work mode", "usage limit"].contains { searchable.contains($0) }
      guard related else { continue }
      let date = parseDate(
        incident.string("resolved_at")
          ?? incident.string("updated_at")
          ?? incident.string("started_at")
      )
      if let date, now.timeIntervalSince(date) <= 36 * 60 * 60 {
        candidates.append((date, incident))
      }
    }
    return candidates.max { $0.0 < $1.0 }?.1
  }

  private func eventDate(_ event: [String: JSONValue]) -> Date? {
    for key in ["effective_at", "announced_at", "observed_at", "at", "date"] {
      if let date = parseDate(event.string(key)) { return date }
    }
    return nil
  }

  private func eventText(_ event: [String: JSONValue]) -> String {
    event.string("text") ?? event.string("summary") ?? ""
  }

  private func eventKind(_ event: [String: JSONValue]) -> String {
    event.string("group") ?? event.string("type") ?? event.string("kind") ?? "signal"
  }

  private func eventURL(_ event: [String: JSONValue]) -> URL? {
    URL(string: event.string("url") ?? event.string("source_url") ?? "")
  }

  private func parseDate(_ value: String?) -> Date? {
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

  private func freshnessDate(in payloads: Dictionary<RadarSource, JSONValue>.Values) -> Date? {
    payloads.compactMap { payload in
      guard let object = payload.objectValue else { return nil }
      return ["updated_at", "fetched_at", "checked_at", "newest_post_at"]
        .compactMap { parseDate(object.string($0)) }
        .max()
    }.max()
  }

  private func likelyWindow(_ forecast: [String: JSONValue]) -> String {
    guard let window = forecast.object("time_window"),
      let start = window.int("start_hour"),
      let end = window.int("end_hour"),
      window.string("timezone") == "UTC"
    else {
      return "北京时间凌晨至上午"
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let startDate = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: start))!
    let endDate = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: end))!
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    formatter.dateFormat = "HH:mm"
    return "北京时间 \(formatter.string(from: startDate))–\(formatter.string(from: endDate))"
  }

  private func containsAny(_ text: String, _ terms: [String]) -> Bool {
    let lowered = text.lowercased()
    return terms.contains { lowered.contains($0) }
  }

  private func clipped(_ text: String, limit: Int = 180) -> String {
    String(text.prefix(limit))
  }

  private func clamp(_ value: Double) -> Int {
    max(1, min(99, Int(value.rounded())))
  }

  private func union(_ first: Int, _ second: Int) -> Int {
    let value = 1 - (1 - Double(first) / 100) * (1 - Double(second) / 100)
    return clamp(value * 100)
  }
}
