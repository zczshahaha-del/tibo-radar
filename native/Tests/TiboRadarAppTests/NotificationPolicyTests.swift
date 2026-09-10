import Foundation
import XCTest

@testable import TiboRadarApp

final class NotificationPolicyTests: XCTestCase {
  func testFirstRunIsSilent() {
    let decision = NotificationPolicy.decide(
      previousSignal: nil,
      previousEventIDs: [],
      snapshot: snapshot(signal: .announced)
    )
    XCTAssertNil(decision)
  }

  func testStrongSignalCrossingNotifiesWithoutPercentage() {
    let decision = NotificationPolicy.decide(
      previousSignal: .weak,
      previousEventIDs: [],
      snapshot: snapshot(signal: .strong)
    )

    XCTAssertNotNil(decision)
    XCTAssertTrue(decision?.title.contains("值得关注") == true)
    XCTAssertFalse(decision?.title.contains("%") == true)
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
      previousSignal: SignalStrength.none,
      previousEventIDs: ["event-1"],
      snapshot: snapshot(signal: .none, events: [event])
    )
    XCTAssertNil(decision)
  }

  private func snapshot(
    signal: SignalStrength,
    events: [RadarEvent] = []
  ) -> PredictionSnapshot {
    PredictionSnapshot(
      generatedAt: Date(timeIntervalSince1970: 0),
      globalSignal: signal,
      bankedSignal: .none,
      affectedUserSignal: nil,
      analysisNote: "test",
      summary: "test",
      likelyWindow: "北京时间 07:00–10:00",
      calibratedProbability: nil,
      probabilityNote: "历史回测仍在实验中，暂不显示概率。",
      lastResetAt: nil,
      dataUpdatedAt: nil,
      isStale: false,
      evidence: [],
      latestEvents: events,
      sourceErrors: []
    )
  }
}
