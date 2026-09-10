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
      globalSignal: .weak,
      bankedSignal: .none,
      affectedUserSignal: nil,
      analysisNote: "test",
      summary: "test",
      likelyWindow: "test",
      probabilityEstimate: ProbabilityEstimate(
        lower24h: 12,
        upper24h: 37,
        lower48h: 25,
        upper48h: 55,
        sampleSize: 307,
        brierScore: 0.106,
        quality: .historicalEstimate
      ),
      probabilityNote: "回放了 307 个过去时段，和旧模型接近；AI 新线索单独显示。",
      lastResetAt: nil,
      dataUpdatedAt: nil,
      isStale: false,
      evidence: [],
      latestEvents: [],
      sourceErrors: []
    )
  }
}
