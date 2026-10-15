import Foundation
import XCTest

@testable import TiboRadarApp

final class RadarHistoryStoreTests: XCTestCase {
  @MainActor
  func testColorsEvidenceAndErrorsSurviveRestart() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = RadarHistoryStore(directory: directory)
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let configuration = AIConfiguration(provider: .deepSeek, model: "test-model")
    for (index, probability) in [39, 40, 69, 70].enumerated() {
      try store.record(event: .refreshSucceeded, configuration: configuration,
        snapshot: snapshot(probability), now: start.addingTimeInterval(Double(index)))
    }
    try store.record(event: .refreshFailed, configuration: configuration,
      snapshot: snapshot(70).markedStale(reason: "offline"), error: "offline", now: start.addingTimeInterval(4))
    let entries = try RadarHistoryStore(directory: directory).load()
    XCTAssertEqual(entries.map(\.color), [.low, .medium, .medium, .high, .high])
    XCTAssertEqual(entries.map(\.recordedAt), (0...4).map { start.addingTimeInterval(Double($0)) })
    XCTAssertEqual(entries.first?.provider, .deepSeek)
    XCTAssertEqual(entries.first?.model, "test-model")
    XCTAssertEqual(entries.last?.error, "offline")
    XCTAssertEqual(entries.last?.snapshot?.isStale, true)
    XCTAssertEqual(entries.last?.snapshot?.evidence.first?.detail, "original reason")
    let text = try String(contentsOf: directory.appendingPathComponent("predictions.json"), encoding: .utf8)
    XCTAssertTrue(text.contains("\"red\""))
    XCTAssertTrue(text.contains("2027-01-15T"))
  }

  @MainActor
  func testRetentionAndEntryLimit() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = RadarHistoryStore(directory: directory, retention: 100, maximumEntries: 2)
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let configuration = AIConfiguration(provider: .qwen, model: "test")
    for offset in [0, 1, 101, 102, 103] {
      try store.record(event: .startup, configuration: configuration, snapshot: nil,
        now: start.addingTimeInterval(Double(offset)))
      XCTAssertLessThanOrEqual(try store.load().count, 2)
    }
    XCTAssertEqual(try store.load().map(\.recordedAt), [102, 103].map { start.addingTimeInterval(Double($0)) })
    try store.record(event: .refreshFailed, configuration: configuration, snapshot: nil,
      error: "no key", now: start.addingTimeInterval(300))
    let entries = try store.load()
    XCTAssertEqual(entries.count, 1)
    XCTAssertEqual(entries.first?.color, .unavailable)
    XCTAssertNil(entries.first?.snapshot)
  }

  @MainActor
  func testUnreadableHistoryIsNotSilentlyOverwritten() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("predictions.json")
    let original = Data("incomplete data".utf8)
    try original.write(to: url)
    let store = RadarHistoryStore(directory: directory)
    XCTAssertThrowsError(try store.record(event: .startup,
      configuration: AIConfiguration(provider: .deepSeek, model: "test"), snapshot: nil))
    XCTAssertEqual(try Data(contentsOf: url), original)
  }

  private func snapshot(_ probability: Int) -> PredictionSnapshot {
    let range = ForecastProbabilityRange(lower: probability, likely: probability, upper: probability)
    return PredictionSnapshot(
      generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
      global24h: range, global48h: range, banked24h: range, banked48h: range,
      combined24h: range, combined48h: range, affectedUserBanked24h: nil,
      usageAdvice: .watch, analysisNote: "test", summary: "test", conditionalWindow: "暂无集中时段",
      historicalBaseline: nil, baselineNote: "test", lastResetAt: nil, dataUpdatedAt: nil, isStale: false,
      evidence: [Evidence(label: "test", detail: "original reason")], latestEvents: [], sourceErrors: []
    )
  }
}
