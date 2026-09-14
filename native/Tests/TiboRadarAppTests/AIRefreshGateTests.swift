import Foundation
import XCTest

@testable import TiboRadarApp

final class AIRefreshGateTests: XCTestCase {
  func testDefaultScheduleWaitsTwoHoursForUnchangedSources() {
    let suite = "TiboRadarRefreshGateTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let gate = AIRefreshGate(defaults: defaults)
    let configuration = AIConfiguration(provider: .qwen, model: "qwen-plus")
    let start = Date(timeIntervalSince1970: 100_000)

    XCTAssertEqual(AIRefreshSchedule.automaticInterval, 7_200)
    XCTAssertEqual(AIRefreshSchedule.label, "每 2 小时检查")
    gate.recordSuccess(
      configuration: configuration,
      sourceFingerprint: "same",
      now: start
    )
    XCTAssertFalse(
      gate.shouldAnalyze(
        configuration: configuration,
        sourceFingerprint: "same",
        now: start.addingTimeInterval(7_199),
        force: false
      )
    )
    XCTAssertTrue(
      gate.shouldAnalyze(
        configuration: configuration,
        sourceFingerprint: "same",
        now: start.addingTimeInterval(7_200),
        force: false
      )
    )
  }

  func testConfiguredIntervalAndSourceChangesAreHonored() {
    let suite = "TiboRadarRefreshGateTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let gate = AIRefreshGate(defaults: defaults, minimumPeriodicInterval: 3_600)
    let configuration = AIConfiguration(provider: .qwen, model: "qwen-plus")
    let start = Date(timeIntervalSince1970: 100_000)

    XCTAssertTrue(
      gate.shouldAnalyze(
        configuration: configuration,
        sourceFingerprint: "same",
        now: start,
        force: false
      )
    )
    gate.recordSuccess(
      configuration: configuration,
      sourceFingerprint: "same",
      now: start
    )
    XCTAssertFalse(
      gate.shouldAnalyze(
        configuration: configuration,
        sourceFingerprint: "same",
        now: start.addingTimeInterval(900),
        force: false
      )
    )
    XCTAssertTrue(
      gate.shouldAnalyze(
        configuration: configuration,
        sourceFingerprint: "changed",
        now: start.addingTimeInterval(900),
        force: false
      )
    )
    XCTAssertTrue(
      gate.shouldAnalyze(
        configuration: configuration,
        sourceFingerprint: "same",
        now: start.addingTimeInterval(3_600),
        force: false
      )
    )
  }

  func testManualRefreshAlwaysUsesAI() {
    let suite = "TiboRadarRefreshGateTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let gate = AIRefreshGate(defaults: defaults)
    let configuration = AIConfiguration(provider: .deepSeek, model: "deepseek-flash")
    let start = Date(timeIntervalSince1970: 100_000)

    gate.recordSuccess(
      configuration: configuration,
      sourceFingerprint: "same",
      now: start
    )

    XCTAssertTrue(
      gate.shouldAnalyze(
        configuration: configuration,
        sourceFingerprint: "same",
        now: start.addingTimeInterval(60),
        force: true
      )
    )
  }
}
