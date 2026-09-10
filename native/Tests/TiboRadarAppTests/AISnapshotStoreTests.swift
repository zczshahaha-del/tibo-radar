import Foundation
import XCTest

@testable import TiboRadarApp

final class AISnapshotStoreTests: XCTestCase {
  func testCacheIsSeparatedByProvider() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("TiboRadarAISnapshotTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AISnapshotStore(directory: directory)
    let snapshot = makeSnapshot()

    try store.save(
      snapshot,
      configuration: AIConfiguration(provider: .deepSeek, model: "deepseek-flash")
    )

    XCTAssertEqual(store.load(for: .deepSeek), snapshot)
    XCTAssertNil(store.load(for: .qwen))
  }

  private func makeSnapshot() -> PredictionSnapshot {
    PredictionSnapshot(
      generatedAt: Date(timeIntervalSince1970: 1),
      global24h: 30,
      global48h: 50,
      banked24h: 10,
      banked48h: 20,
      combined24h: 37,
      combined48h: 60,
      affectedUserBanked24h: nil,
      confidence: "medium",
      confidenceNote: "test",
      level: .green,
      likelyWindow: "test",
      lastResetAt: nil,
      dataUpdatedAt: nil,
      isStale: false,
      evidence: [],
      latestEvents: [],
      sourceErrors: []
    )
  }
}
