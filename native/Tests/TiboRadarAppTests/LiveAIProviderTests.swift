import Foundation
import XCTest

@testable import TiboRadarApp

final class LiveAIProviderTests: XCTestCase {
  func testSavedDeepSeekKeyProducesProbabilityForecast() async throws {
    guard ProcessInfo.processInfo.environment["TIBO_RADAR_LIVE_AI_TEST"] == "1" else {
      throw XCTSkip("Set TIBO_RADAR_LIVE_AI_TEST=1 to call the saved DeepSeek account")
    }
    guard let apiKey = try KeychainAPIKeyStore().read(for: .deepSeek), !apiKey.isEmpty else {
      throw XCTSkip("No saved DeepSeek key")
    }

    let cache = FileManager.default.temporaryDirectory
      .appendingPathComponent("TiboRadarLiveAITest-\(UUID().uuidString)")
    let bundle = await RadarClient(cacheDirectory: cache).fetchAll()
    let context = try AIInputBuilder.makeContext(bundle: bundle)
    let analysis = try await AIProviderClient().analyze(
      context: context,
      configuration: AIConfiguration(provider: .deepSeek, model: "deepseek-flash"),
      apiKey: apiKey
    )
    let snapshot = analysis.snapshot(bundle: bundle)

    XCTAssertGreaterThan(snapshot.global24h.lower, 0)
    XCTAssertGreaterThan(snapshot.banked24h.lower, 0)
    XCTAssertGreaterThan(snapshot.combined24h.lower, 0)
    XCTAssertGreaterThanOrEqual(snapshot.combined48h.likely, snapshot.combined24h.likely)
    XCTAssertGreaterThanOrEqual(snapshot.combined24h.likely, snapshot.global24h.likely)
    XCTAssertGreaterThanOrEqual(snapshot.combined24h.likely, snapshot.banked24h.likely)
    XCTAssertNotNil(snapshot.historicalBaseline)
    XCTAssertFalse(snapshot.analysisNote.contains("%"))
    XCTAssertFalse(snapshot.summary.contains("%"))
  }
}
