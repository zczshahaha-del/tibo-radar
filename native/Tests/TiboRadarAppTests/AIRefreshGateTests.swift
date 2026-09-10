import Foundation
import XCTest

@testable import TiboRadarApp

final class AIRefreshGateTests: XCTestCase {
  func testPeriodicRefreshSkipsUnchangedSourcesForOneHour() {
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

    XCTAssertTrue(
      gate.shouldAnalyze(
        configuration: AIConfiguration(provider: .deepSeek, model: "deepseek-flash"),
        sourceFingerprint: "same",
        force: true
      )
    )
  }
}
