import Foundation
import XCTest

@testable import TiboRadarApp

final class PredictorTests: XCTestCase {
  private let now = ISO8601DateFormatter().date(from: "2026-09-10T12:00:00Z")!

  func testTargetedCompensationDoesNotInflateBroadBankedProbability() throws {
    let event = """
      {
        "id": "credits-targeted",
        "group": "credits",
        "text": "Banked resets are arriving for affected users without access.",
        "announced_at": "2026-09-09T20:00:00Z",
        "banked_state": "arriving"
      }
      """
    let snapshot = Predictor().predict(bundle: try bundle(events: [event]), now: now)

    XCTAssertEqual(snapshot.banked24h, 8)
    XCTAssertEqual(snapshot.affectedUserBanked24h, 94)
    XCTAssertTrue(snapshot.evidence.contains { $0.category == "targeted" })
  }

  func testExplicitGlobalFutureResetIsHighProbability() throws {
    let event = """
      {
        "id": "global-future",
        "group": "reset",
        "text": "All paid Codex users will reset tomorrow.",
        "announced_at": "2026-09-10T10:00:00Z"
      }
      """
    let snapshot = Predictor().predict(bundle: try bundle(events: [event]), now: now)

    XCTAssertGreaterThanOrEqual(snapshot.global24h, 88)
    XCTAssertGreaterThanOrEqual(snapshot.global48h, snapshot.global24h)
    XCTAssertEqual(snapshot.confidence, "high")
  }

  func testBroadBankedAnnouncementStaysSeparateFromGlobalReset() throws {
    let event = """
      {
        "id": "banked-global",
        "group": "credits",
        "text": "Banked reset credits are arriving for everyone.",
        "announced_at": "2026-09-10T10:00:00Z",
        "banked_state": "arriving"
      }
      """
    let snapshot = Predictor().predict(bundle: try bundle(events: [event]), now: now)

    XCTAssertEqual(snapshot.global24h, 27)
    XCTAssertEqual(snapshot.banked24h, 94)
    XCTAssertGreaterThan(snapshot.combined24h, 94)
  }

  func testCacheFallbackMarksSnapshotStale() throws {
    var sourceBundle = try bundle(events: [])
    sourceBundle.cacheFallbacks = [.forecast]

    let snapshot = Predictor().predict(bundle: sourceBundle, now: now)

    XCTAssertTrue(snapshot.isStale)
    XCTAssertEqual(snapshot.confidence, "low")
  }

  private func bundle(events: [String]) throws -> SourceBundle {
    let eventValues = try events.map(decode)
    let forecast = try decode(
      """
      {
        "probabilities": {"rounded_24h": 27, "rounded_48h": 47},
        "last_reset_at": "2026-09-08T04:05:53Z",
        "age_days": 2.3,
        "cadence": {"recent_median_days": 2.1},
        "confidence": "low",
        "time_window": {"start_hour": 23, "end_hour": 2, "timezone": "UTC"},
        "updated_at": "2026-09-10T11:55:00Z"
      }
      """)
    return SourceBundle(
      payloads: [
        .forecast: forecast,
        .timeline: .object([
          "events": .array(eventValues),
          "updated_at": .string("2026-09-10T11:55:00Z"),
        ]),
        .feed: .object(["events": .array([])]),
        .openAIStatus: .object(["incidents": .array([])]),
      ],
      cacheFallbacks: [],
      errors: []
    )
  }

  private func decode(_ json: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
  }
}
