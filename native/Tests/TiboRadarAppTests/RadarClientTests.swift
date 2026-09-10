import Foundation
import XCTest
@testable import TiboRadarApp

private final class FailingURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        client?.urlProtocol(
            self,
            didFailWithError: URLError(.notConnectedToInternet)
        )
    }

    override func stopLoading() {}
}

final class RadarClientTests: XCTestCase {
    func testNetworkFailureFallsBackToAllCachedSources() async throws {
        let cache = FileManager.default.temporaryDirectory
            .appendingPathComponent("TiboRadarCacheTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let cached = JSONValue.object([
            "updated_at": .string("2026-09-10T00:00:00Z"),
        ])
        let data = try JSONEncoder().encode(cached)
        for source in RadarSource.allCases {
            try data.write(
                to: cache.appendingPathComponent("\(source.rawValue).json"),
                options: .atomic
            )
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FailingURLProtocol.self]
        let client = RadarClient(
            session: URLSession(configuration: configuration),
            cacheDirectory: cache
        )
        let bundle = await client.fetchAll()

        XCTAssertEqual(bundle.payloads.count, RadarSource.allCases.count)
        XCTAssertEqual(bundle.cacheFallbacks, Set(RadarSource.allCases))
        XCTAssertEqual(bundle.errors.count, RadarSource.allCases.count)
    }
}
