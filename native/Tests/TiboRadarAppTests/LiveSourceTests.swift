import Foundation
import XCTest

@testable import TiboRadarApp

final class LiveSourceTests: XCTestCase {
  func testGeneralActivityResolvesRealReplyThread() async throws {
    guard ProcessInfo.processInfo.environment["TIBO_RADAR_LIVE_TEST"] == "1" else {
      throw XCTSkip("Set TIBO_RADAR_LIVE_TEST=1 to check public reply context")
    }
    let cache = FileManager.default.temporaryDirectory
      .appendingPathComponent("TiboRadarLiveReply-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: cache) }
    let feed: JSONValue = .object([
      "radar_context": .array([.object([
        "id": .string("2101920928070562029"),
        "text": .string("3am on a tuesday"),
        "visibility_only": .bool(true),
      ])])
    ])
    let enriched = await RadarClient(cacheDirectory: cache).enrichReplyContexts(in: feed)
    let reply = try XCTUnwrap(enriched.objectValue?.array("radar_context")?.first?.objectValue)
    XCTAssertEqual(reply.string("in_reply_to_tweet_id"), "2101792478747906307")
    let parent = try XCTUnwrap(reply.object("reply_context")?.object("parent"))
    XCTAssertEqual(parent.string("id"), "2101792478747906307")
    XCTAssertFalse((parent.string("text") ?? "").isEmpty)
    let input = try AIInputBuilder.makeContext(bundle: SourceBundle(payloads: [.feed: enriched], cacheFallbacks: [], errors: []))
    XCTAssertTrue(input.contains("\"reply_context_status\":\"available\""))
  }

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
    XCTAssertTrue(context.contains("tibo_feed_freshness"))
    XCTAssertTrue(context.contains("recent_tibo_feed"))
    XCTAssertTrue(context.contains("recent_tibo_posts"))
    XCTAssertTrue(context.contains("recent_tibo_context"))
    XCTAssertTrue(context.contains("rounded_24h"))
  }
}
