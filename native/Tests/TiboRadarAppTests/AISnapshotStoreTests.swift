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
      calibratedProbability: nil,
      probabilityNote: "历史回测仍在实验中，暂不显示概率。",
      lastResetAt: nil,
      dataUpdatedAt: nil,
      isStale: false,
      evidence: [],
      latestEvents: [],
      sourceErrors: []
    )
  }
}
