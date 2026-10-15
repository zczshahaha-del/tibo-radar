import Foundation
import CryptoKit

enum AIChangeDetector {
  static func fingerprint(bundle: SourceBundle) throws -> String {
    var payloads: [RadarSource: JSONValue] = [:]
    if let feed = bundle.payloads[.feed]?.objectValue {
      let posts = Array((feed.array("tweets") ?? []).prefix(12))
      let context = Array((feed.array("radar_context") ?? []).prefix(12)).filter(isPotentialSignal)
      payloads[.feed] = .object([
        "events": try events(feed.array("events") ?? []),
        "tweets": try postsValue(posts),
        "radar_context": try postsValue(context),
      ])
    }
    if let timeline = bundle.payloads[.timeline]?.objectValue {
      payloads[.timeline] = .object(["events": try events(timeline.array("events") ?? [])])
    }
    for source in [RadarSource.status, .openAIStatus] {
      if let status = bundle.payloads[source]?.objectValue {
        let incidents = (status.array("incidents") ?? []).prefix(15).compactMap { value -> JSONValue? in
          guard let incident = value.objectValue else { return nil }
          var result = selecting([
            "id", "name", "status", "impact", "started_at", "resolved_at", "codex_related",
          ], from: incident)
          let updates = incident.array("incident_updates") ?? incident.array("updates") ?? []
          result["updates"] = .array(updates.compactMap { update in
            update.objectValue.map { .object(selecting(["id", "status", "body"], from: $0)) }
          })
          return .object(result)
        }
        payloads[source] = .object(["incidents": try sorted(incidents)])
      }
    }
    // Collection errors and baseline drift are handled by source warnings and the
    // periodic AI forecast; they must not turn every five-minute poll into an AI call.
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let content = Dictionary(uniqueKeysWithValues: payloads.map { ($0.key.rawValue, $0.value) })
    return SHA256.hash(data: try encoder.encode(content))
      .map { String(format: "%02x", $0) }.joined()
  }

  private static func isPotentialSignal(_ value: JSONValue) -> Bool {
    guard let post = value.objectValue else { return false }
    let isReply = post.bool("is_reply") == true
      || !(post.string("in_reply_to_tweet_id") ?? "").isEmpty
    // New standalone posts and unresolved replies are deliberately conservative:
    // short phrases and missing parents have contained real reset hints before.
    guard isReply else { return true }
    let context = post.object("reply_context") ?? [:]
    let parent = context.object("parent")?.string("text") ?? ""
    let quote = context.object("quoted_post")?.string("text") ?? ""
    guard !parent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
    let text = [post.string("text") ?? "", parent, quote].joined(separator: "\n")
    let pattern = #"(?i)\b(reset|banked|credits?|quota|limits?|compensat\w*|ship\w*|launch\w*|releas\w*|rollout|tomorrow|today|tonight|midnight|monday|tuesday|wednesday|thursday|friday|saturday|sunday|eod|pst|pdt|\d+\s*(am|pm|hours?|days?))\b|重置|补偿|额度|重置卡|发卡|明天|今晚|月底|北京时间"#
    return text.range(of: pattern, options: .regularExpression) != nil
  }

  private static func postsValue(_ posts: [JSONValue]) throws -> JSONValue {
    try sorted(posts.compactMap { value in
      guard let post = value.objectValue else { return nil }
      var result = selecting([
        "id", "at", "text", "url", "is_reply", "in_reply_to_tweet_id", "replying_to",
      ], from: post)
      if let context = post.object("reply_context") {
        result["reply_context"] = .object(context.compactMapValues { value in
          value.objectValue.map { .object(selecting(["id", "at", "text", "url"], from: $0)) }
        })
      }
      return .object(result)
    })
  }

  private static func events(_ values: [JSONValue]) throws -> JSONValue {
    try sorted(values.prefix(40).compactMap { value in
      value.objectValue.map {
        .object(selecting([
          "id", "group", "kind", "type", "text", "summary", "url", "source_url",
          "announced_at", "effective_at", "announcement_state", "banked_state",
          "reset_verification_status", "observation_result", "audience", "scope", "official_window",
        ], from: $0))
      }
    })
  }

  private static func selecting(_ keys: [String], from object: [String: JSONValue]) -> [String: JSONValue] {
    object.filter { keys.contains($0.key) }
  }

  private static func sorted(_ values: [JSONValue]) throws -> JSONValue {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let keyed = try values.map { ($0, try encoder.encode($0)) }
    return .array(keyed.sorted { $0.1.lexicographicallyPrecedes($1.1) }.map(\.0))
  }
}
