import Foundation
import CryptoKit

enum AIInputBuilder {
  static func makeContext(bundle: SourceBundle, now: Date = Date()) throws -> String {
    try serializedContext(bundle: bundle, now: now)
  }

  static func fingerprint(bundle: SourceBundle) throws -> String {
    let stableContext = try serializedContext(
      bundle: bundle,
      now: Date(timeIntervalSince1970: 0)
    )
    return SHA256.hash(data: Data(stableContext.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
  }

  private static func serializedContext(bundle: SourceBundle, now: Date) throws -> String {
    var context: [String: Any] = [
      "current_time": ISO8601DateFormatter().string(from: now),
      "timezone": "Asia/Shanghai",
    ]

    if let forecast = bundle.payloads[.forecast]?.objectValue {
      context["historical_baseline"] = jsonObject(
        selecting: [
          "last_reset_at", "age_days", "cadence", "time_window", "probabilities",
          "backtest", "model", "wait_comparison",
        ],
        from: forecast
      )
    }
    if let timeline = bundle.payloads[.timeline]?.objectValue {
      context["historical_events"] = trimmedArray(timeline["events"], limit: 40)
    }
    if let feed = bundle.payloads[.feed]?.objectValue {
      context["tibo_feed_freshness"] = jsonObject(
        selecting: [
          "fetched_at", "newest_post_at", "signal_newest_post_at", "content_age_days", "stale",
        ],
        from: feed
      )
      context["recent_tibo_feed"] = trimmedObjects(
        feed["events"],
        limit: 40,
        selecting: [
          "id", "announced_at", "observed_at", "effective_at", "summary", "text",
          "url", "source_label", "source",
        ]
      )
      context["recent_tibo_posts"] = recentTiboPosts(feed["tweets"], limit: 12)
      context["recent_tibo_context"] = recentTiboContext(
        feed["radar_context"],
        limit: 12
      )
    }
    if let status = bundle.payloads[.status]?.objectValue {
      context["aggregated_status_incidents"] = trimmedArray(status["incidents"], limit: 15)
    }
    if let openAI = bundle.payloads[.openAIStatus]?.objectValue {
      context["openai_status_incidents"] = trimmedArray(openAI["incidents"], limit: 15)
    }
    context["source_errors"] = bundle.errors

    let data = try JSONSerialization.data(
      withJSONObject: context,
      options: [.sortedKeys]
    )
    guard let text = String(data: data, encoding: .utf8) else {
      throw AIProviderError.invalidAnalysis("无法整理公开来源数据。")
    }
    return text
  }

  private static func jsonObject(
    selecting keys: [String],
    from object: [String: JSONValue]
  ) -> [String: Any] {
    var result: [String: Any] = [:]
    for key in keys {
      if let value = object[key] {
        result[key] = foundationValue(value)
      }
    }
    return result
  }

  private static func trimmedArray(_ value: JSONValue?, limit: Int) -> [Any] {
    guard let values = value?.arrayValue else { return [] }
    return values.prefix(limit).map(foundationValue)
  }

  private static func trimmedObjects(
    _ value: JSONValue?,
    limit: Int,
    selecting keys: [String]
  ) -> [[String: Any]] {
    guard let values = value?.arrayValue else { return [] }
    return values.prefix(limit).compactMap { value in
      guard let object = value.objectValue else { return nil }
      return jsonObject(selecting: keys, from: object)
    }
  }

  private static func recentTiboPosts(
    _ value: JSONValue?,
    limit: Int
  ) -> [[String: Any]] {
    guard let values = value?.arrayValue else { return [] }
    return values.prefix(limit).compactMap { value in
      guard let post = value.objectValue else { return nil }
      var result = jsonObject(
        selecting: [
          "id", "at", "declared_at", "text", "url", "is_reply",
          "replying_to", "in_reply_to_tweet_id", "conversation_id", "reply_context",
        ],
        from: post
      )
      if post.bool("is_reply") == true {
        result["reply_context_status"] =
          post.object("reply_context") == nil ? "missing" : "available"
      }
      if let text = post.string("text") {
        result["text"] = boundedPostText(text)
        result["closing_paragraph"] = closingParagraph(text)
      }
      appendLocalTimes(from: post, to: &result)
      return result
    }
  }

  private static func recentTiboContext(
    _ value: JSONValue?,
    limit: Int
  ) -> [[String: Any]] {
    guard let values = value?.arrayValue else { return [] }
    return values.prefix(limit).compactMap { value in
      guard let post = value.objectValue else { return nil }
      var result = jsonObject(
        selecting: [
          "id", "at", "text", "url", "display_kind", "visibility_only",
        ],
        from: post
      )
      appendLocalTimes(from: post, to: &result)
      return result
    }
  }

  private static func appendLocalTimes(
    from post: [String: JSONValue],
    to result: inout [String: Any]
  ) {
    guard let rawDate = post.string("at"),
      let date = ISO8601DateFormatter().date(from: rawDate)
    else { return }
    result["published_at_beijing"] = formatted(date, timeZone: "Asia/Shanghai")
    result["published_at_pacific"] = formatted(date, timeZone: "America/Los_Angeles")
  }

  private static func formatted(_ date: Date, timeZone identifier: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: identifier)
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXX"
    return formatter.string(from: date)
  }

  private static func closingParagraph(_ text: String) -> String {
    let paragraphs = text.components(separatedBy: "\n\n")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    return String((paragraphs.last ?? text).suffix(2_000))
  }

  private static func boundedPostText(_ text: String) -> String {
    let maximumCharacters = 6_000
    guard text.count > maximumCharacters else { return text }
    return String(text.prefix(4_000))
      + "\n[…中间内容已压缩，保留帖子末尾…]\n"
      + String(text.suffix(2_000))
  }

  private static func foundationValue(_ value: JSONValue) -> Any {
    switch value {
    case .object(let object):
      return object.mapValues(foundationValue)
    case .array(let values):
      return values.map(foundationValue)
    case .string(let string):
      return String(string.prefix(2_000))
    case .number(let number):
      return number
    case .bool(let bool):
      return bool
    case .null:
      return NSNull()
    }
  }
}
