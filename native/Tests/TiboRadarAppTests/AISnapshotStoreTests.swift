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
      global24h: ForecastProbabilityRange(lower: 8, likely: 15, upper: 25),
      global48h: ForecastProbabilityRange(lower: 15, likely: 28, upper: 42),
      banked24h: ForecastProbabilityRange(lower: 4, likely: 8, upper: 14),
      banked48h: ForecastProbabilityRange(lower: 8, likely: 16, upper: 26),
      combined24h: ForecastProbabilityRange(lower: 10, likely: 21, upper: 32),
      combined48h: ForecastProbabilityRange(lower: 19, likely: 38, upper: 55),
      affectedUserBanked24h: nil,
      usageAdvice: .watch,
      analysisNote: "test",
      summary: "test",
      likelyWindow: "test",
      historicalBaseline: ProbabilityEstimate(
        lower24h: 12,
        upper24h: 37,
        lower48h: 25,
        upper48h: 55,
        sampleSize: 307,
        brierScore: 0.106,
        quality: .historicalEstimate
      ),
      baselineNote: "AI 参考历史基准：24 小时 12–37%，48 小时 25–55%，共 307 个回放时段。",
      lastResetAt: nil,
      dataUpdatedAt: nil,
      isStale: false,
      evidence: [],
      latestEvents: [],
      sourceErrors: []
    )
  }
}
