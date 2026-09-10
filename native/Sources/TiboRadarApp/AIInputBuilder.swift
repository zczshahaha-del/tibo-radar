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
      context["recent_tibo_feed"] = trimmedArray(feed["events"], limit: 40)
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
