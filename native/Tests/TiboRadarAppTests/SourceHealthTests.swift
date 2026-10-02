import Foundation
import XCTest

@testable import TiboRadarApp

final class SourceHealthTests: XCTestCase {
  private let now = SourceMetadata.parseDate("2026-10-03T02:00:00Z")!

  func testFreshPollDoesNotRequireRecentPostsOrIncidents() {
    var bundle = freshBundle()
    bundle.payloads[.feed] = .object([
      "fetched_at": .string("2026-10-03T01:59:00Z"),
      "newest_post_at": .string("2026-09-20T00:00:00Z"),
    ])
    bundle.payloads[.openAIStatus] = .object([
      "incidents": .array([.object(["created_at": .string("2026-09-01T00:00:00Z")])])
    ])
    XCTAssertTrue(SourceHealth.assess(bundle: bundle, now: now).allSatisfy { $0.state == .fresh })
  }

  func testOneDegradedSourceCannotBeHiddenByTheOthers() {
    for source in RadarSource.allCases {
      var bundle = freshBundle()
      bundle.payloads.removeValue(forKey: source)
      XCTAssertEqual(health(source, in: bundle).state, .missing)

      bundle.payloads[source] = .object(["fetched_at": .string("2026-10-02T01:00:00Z")])
      XCTAssertEqual(health(source, in: bundle).state, .stale)

      bundle.payloads[source] = .object(["stale": .bool(true)])
      XCTAssertEqual(health(source, in: bundle).state, .stale)

      bundle.payloads[source] = .object([:])
      bundle.cacheFallbacks.insert(source)
      XCTAssertEqual(health(source, in: bundle).state, .cached)
    }
  }

  func testUnknownAndFutureTimesDoNotBecomeFresh() {
    var bundle = freshBundle()
    bundle.receivedAt.removeValue(forKey: .feed)
    bundle.payloads[.feed] = .object(["newest_post_at": .string("2026-10-03T02:00:00Z")])
    XCTAssertEqual(health(.feed, in: bundle).state, .unknown)
    bundle.payloads[.feed] = .object(["fetched_at": .string("2026-10-04T02:00:00Z")])
    XCTAssertEqual(health(.feed, in: bundle).state, .unknown)
  }

  func testFreshContentTimestampDoesNotMaskOldCollectionTime() {
    var bundle = freshBundle()
    bundle.payloads[.feed] = .object([
      "fetched_at": .string("2026-10-02T02:00:00Z"),
      "updated_at": .string("2026-10-03T02:00:00Z"),
    ])
    XCTAssertEqual(health(.feed, in: bundle).state, .stale)
  }

  func testHealthWarningsReachAIAndReceiptTimeDoesNotInvalidateFingerprint() throws {
    var bundle = freshBundle()
    bundle.payloads.removeValue(forKey: .feed)
    let context = try AIInputBuilder.makeContext(bundle: bundle, now: now)
    let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(context.utf8)) as? [String: Any])
    let health = try XCTUnwrap(root["source_health"] as? [[String: Any]])
    XCTAssertEqual(health.first { $0["source"] as? String == "feed" }?["state"] as? String, "missing")
    let original = try AIInputBuilder.fingerprint(bundle: bundle)
    bundle.receivedAt = bundle.receivedAt.mapValues { $0.addingTimeInterval(60) }
    XCTAssertEqual(try AIInputBuilder.fingerprint(bundle: bundle), original)
    bundle.cacheFallbacks.insert(.forecast)
    XCTAssertNotEqual(try AIInputBuilder.fingerprint(bundle: bundle), original)
  }

  private func freshBundle() -> SourceBundle {
    SourceBundle(
      payloads: Dictionary(uniqueKeysWithValues: RadarSource.allCases.map { ($0, JSONValue.object([:])) }),
      cacheFallbacks: [], errors: [],
      receivedAt: Dictionary(uniqueKeysWithValues: RadarSource.allCases.map { ($0, now) })
    )
  }

  private func health(_ source: RadarSource, in bundle: SourceBundle) -> SourceHealth {
    SourceHealth.assess(bundle: bundle, now: now).first { $0.source == source }!
  }
}
