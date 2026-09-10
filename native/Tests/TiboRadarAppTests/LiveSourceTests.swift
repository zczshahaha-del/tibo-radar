import Foundation
import XCTest
@testable import TiboRadarApp

final class LiveSourceTests: XCTestCase {
    func testLiveSourcesProduceUsableSnapshot() async throws {
        guard ProcessInfo.processInfo.environment["TIBO_RADAR_LIVE_TEST"] == "1" else {
            throw XCTSkip("Set TIBO_RADAR_LIVE_TEST=1 to check public sources")
        }
        let cache = FileManager.default.temporaryDirectory
            .appendingPathComponent("TiboRadarLiveTest-\(UUID().uuidString)")
        let bundle = await RadarClient(cacheDirectory: cache).fetchAll()
        let snapshot = Predictor().predict(bundle: bundle)

        XCTAssertNotNil(bundle.payloads[.forecast])
        XCTAssertNotNil(bundle.payloads[.timeline])
        XCTAssertFalse(snapshot.latestEvents.isEmpty)
        XCTAssertTrue((1 ... 99).contains(snapshot.combined24h))
        print(
            "LIVE SNAPSHOT: 24h=\(snapshot.combined24h)% "
                + "48h=\(snapshot.combined48h)% level=\(snapshot.level.label)"
        )
    }
}
