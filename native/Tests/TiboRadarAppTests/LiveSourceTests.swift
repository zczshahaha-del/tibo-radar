import Foundation
import XCTest

@testable import TiboRadarApp

final class LiveSourceTests: XCTestCase {
  func testLiveSourcesProduceAIContext() async throws {
    guard ProcessInfo.processInfo.environment["TIBO_RADAR_LIVE_TEST"] == "1" else {
      throw XCTSkip("Set TIBO_RADAR_LIVE_TEST=1 to check public sources")
    }
    let cache = FileManager.default.temporaryDirectory
      .appendingPathComponent("TiboRadarLiveTest-\(UUID().uuidString)")
    let bundle = await RadarClient(cacheDirectory: cache).fetchAll()
    let context = try AIInputBuilder.makeContext(bundle: bundle)
    let metadata = SourceMetadata(bundle: bundle)

    XCTAssertNotNil(bundle.payloads[.forecast])
    XCTAssertNotNil(bundle.payloads[.timeline])
    XCTAssertFalse(metadata.latestEvents.isEmpty)
    XCTAssertTrue(context.contains("recent_tibo_feed"))
    XCTAssertTrue(context.contains("rounded_24h"))
  }
}
