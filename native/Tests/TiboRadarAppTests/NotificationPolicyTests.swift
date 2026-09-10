import Foundation
import XCTest

@testable import TiboRadarApp

final class NotificationPolicyTests: XCTestCase {
  func testFirstRunIsSilent() {
    let decision = NotificationPolicy.decide(
      previousProbability: nil,
      previousEventIDs: [],
      snapshot: snapshot(likely: 80)
    )
    XCTAssertNil(decision)
  }

  func testProbabilityThresholdCrossingNotifiesWithRange() {
    let decision = NotificationPolicy.decide(
      previousProbability: 42,
      previousEventIDs: [],
      snapshot: snapshot(likely: 72)
    )

    XCTAssertNotNil(decision)
    XCTAssertTrue(decision?.title.contains("62–82%") == true)
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
      previousProbability: 15,
      previousEventIDs: ["event-1"],
      snapshot: snapshot(likely: 15, events: [event])
    )
    XCTAssertNil(decision)
  }

  private func snapshot(
    likely: Int,
    events: [RadarEvent] = []
  ) -> PredictionSnapshot {
    PredictionSnapshot(
      generatedAt: Date(timeIntervalSince1970: 0),
      global24h: ForecastProbabilityRange(lower: 8, likely: max(8, likely - 8), upper: max(18, likely + 5)),
      global48h: ForecastProbabilityRange(lower: 15, likely: max(15, likely), upper: max(30, likely + 12)),
      banked24h: ForecastProbabilityRange(lower: 4, likely: 7, upper: 12),
      banked48h: ForecastProbabilityRange(lower: 8, likely: 14, upper: 24),
      combined24h: ForecastProbabilityRange(lower: max(10, likely - 10), likely: likely, upper: max(20, likely + 10)),
      combined48h: ForecastProbabilityRange(lower: max(18, likely), likely: max(30, likely + 10), upper: max(40, likely + 18)),
      affectedUserBanked24h: nil,
      usageAdvice: .watch,
      analysisNote: "test",
      summary: "test",
      likelyWindow: "北京时间 07:00–10:00",
      historicalBaseline: nil,
      baselineNote: "没有拿到历史回放数据。",
      lastResetAt: nil,
      dataUpdatedAt: nil,
      isStale: false,
      evidence: [],
      latestEvents: events,
      sourceErrors: []
    )
  }
}
