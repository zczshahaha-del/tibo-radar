import Foundation
import XCTest

@testable import TiboRadarApp

final class NotificationPolicyTests: XCTestCase {
  func testFirstRunIsSilent() {
    let decision = NotificationPolicy.decide(
      previousProbability: nil,
      previousEventIDs: [],
      snapshot: snapshot(probability: 80)
    )
    XCTAssertNil(decision)
  }

  func testThresholdCrossingNotifies() {
    let decision = NotificationPolicy.decide(
      previousProbability: 50,
      previousEventIDs: [],
      snapshot: snapshot(probability: 70)
    )
    XCTAssertNotNil(decision)
    XCTAssertTrue(decision?.title.contains("70%") == true)
  }

  func testKnownEventDoesNotNotifyAgain() {
    let event = RadarEvent(
      id: "event-1",
      kind: "reset",
      title: "Reset tomorrow",
      occurredAt: nil,
      sourceURL: nil,
      state: nil
    )
    let decision = NotificationPolicy.decide(
      previousProbability: 40,
      previousEventIDs: ["event-1"],
      snapshot: snapshot(probability: 40, events: [event])
    )
    XCTAssertNil(decision)
  }

  private func snapshot(
    probability: Int,
    events: [RadarEvent] = []
  ) -> PredictionSnapshot {
    PredictionSnapshot(
      generatedAt: Date(timeIntervalSince1970: 0),
      global24h: probability,
      global48h: probability,
      banked24h: 8,
      banked48h: 15,
      combined24h: probability,
      combined48h: probability,
      affectedUserBanked24h: nil,
      confidence: "low",
      confidenceNote: "test",
      level: .green,
      likelyWindow: "北京时间 07:00–10:00",
      lastResetAt: nil,
      dataUpdatedAt: nil,
      isStale: false,
      evidence: [],
      latestEvents: events,
      sourceErrors: []
    )
  }
}
