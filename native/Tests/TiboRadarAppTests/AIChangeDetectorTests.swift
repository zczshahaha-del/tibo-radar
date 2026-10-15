import Foundation
import XCTest

@testable import TiboRadarApp

final class AIChangeDetectorTests: XCTestCase {
  func testKnownUnrelatedRepliesDoNotTriggerAI() throws {
    let original = bundle(context: [])
    let chatter = bundle(context: [reply("Thanks!", parent: "Nice wallpaper")])
    XCTAssertEqual(try fingerprint(original), try fingerprint(chatter))
    XCTAssertTrue(try AIInputBuilder.makeContext(bundle: chatter).contains("Nice wallpaper"))
  }

  func testResetParentQuoteAndTimeHintsTriggerAI() throws {
    let original = try fingerprint(bundle(context: []))
    for post in [
      reply("OK fine", parent: "You owe us a banked reset"),
      reply("3am on a Tuesday", parent: "When does this happen?"),
      JSONValue.object(["id": .string("unknown"), "text": .string("OK fine"), "is_reply": .bool(true)]),
      JSONValue.object(["id": .string("new"), "text": .string("Done and dusted"), "is_reply": .bool(false)]),
      JSONValue.object([
        "id": .string("quoted"), "text": .string("Yes"), "is_reply": .bool(true),
        "reply_context": .object([
          "parent": .object(["text": .string("Agree with this?")]),
          "quoted_post": .object(["text": .string("Banked reset for everyone")]),
        ]),
      ]),
    ] {
      XCTAssertNotEqual(try fingerprint(bundle(context: [post])), original)
    }
  }

  func testMetricsOrderingAndBaselineDriftDoNotTriggerAI() throws {
    var original = bundle(context: [])
    original.payloads[.feed] = .object([
      "tweets": .array([
        .object(["id": .string("1"), "text": .string("Reset tonight"), "likes": .number(1)]),
        .object(["id": .string("2"), "text": .string("Another announcement")]),
      ]),
    ])
    var changed = original
    changed.payloads[.feed] = .object([
      "fetched_at": .string("2026-10-15T10:00:00Z"),
      "tweets": .array([
        .object(["id": .string("2"), "text": .string("Another announcement")]),
        .object(["id": .string("1"), "text": .string("Reset tonight"), "likes": .number(50)]),
      ]),
    ])
    changed.payloads[.forecast] = .object(["probabilities": .object(["rounded_24h": .number(47)])])
    changed.cacheFallbacks.insert(.status)
    changed.errors = ["temporary source error"]
    XCTAssertEqual(try fingerprint(changed), try fingerprint(original))
  }

  func testDeliveryStateAndIncidentUpdatesAreImportant() throws {
    var original = bundle(context: [])
    original.payloads[.feed] = .object(["events": .array([.object([
      "id": .string("card"), "banked_state": .string("announced"),
    ])])])
    var delivered = original
    delivered.payloads[.feed] = .object(["events": .array([.object([
      "id": .string("card"), "banked_state": .string("available"),
    ])])])
    XCTAssertNotEqual(try fingerprint(original), try fingerprint(delivered))
    var incident = original
    incident.payloads[.openAIStatus] = .object(["incidents": .array([.object([
      "id": .string("outage"), "name": .string("Codex errors"), "status": .string("investigating"),
      "incident_updates": .array([.object(["body": .string("Investigating failures")])]),
    ])])])
    XCTAssertNotEqual(try fingerprint(incident), try fingerprint(original))
    var resolved = incident
    resolved.payloads[.openAIStatus] = .object(["incidents": .array([.object([
      "id": .string("outage"), "name": .string("Codex errors"), "status": .string("resolved"),
      "incident_updates": .array([.object(["body": .string("Fully recovered")])]),
    ])])])
    XCTAssertNotEqual(try fingerprint(incident), try fingerprint(resolved))
  }

  private func fingerprint(_ bundle: SourceBundle) throws -> String {
    try AIInputBuilder.fingerprint(bundle: bundle)
  }

  private func bundle(context: [JSONValue]) -> SourceBundle {
    SourceBundle(payloads: [.feed: .object(["radar_context": .array(context)])], cacheFallbacks: [], errors: [])
  }

  private func reply(_ text: String, parent: String) -> JSONValue {
    .object([
      "id": .string("reply"), "text": .string(text), "is_reply": .bool(true),
      "reply_context": .object(["parent": .object(["text": .string(parent)])]),
    ])
  }
}
