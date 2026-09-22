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

private final class ReplyContextURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var responseData: Data?

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let data = Self.responseData else {
      client?.urlProtocol(self, didFailWithError: URLError(.unknown))
      return
    }
    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: 200,
      httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

private struct StubReplyContextClient: ReplyContextFetching {
  let contexts: [String: JSONValue]

  func fetchContext(parentTweetID: String) async -> JSONValue? {
    contexts[parentTweetID]
  }
}

final class RadarClientTests: XCTestCase {
  override func tearDown() {
    ReplyContextURLProtocol.responseData = nil
    super.tearDown()
  }

  func testNetworkFailureFallsBackToAllCachedSources() async throws {
    let cache = FileManager.default.temporaryDirectory
      .appendingPathComponent("TiboRadarCacheTest-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    let cached = JSONValue.object([
      "updated_at": .string("2026-09-10T00:00:00Z")
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

  func testPublicReplyContextClientReadsParentAndQuotedPost() async throws {
    let response: [String: Any] = [
      "tweet": [
        "id": "2101093319501664368",
        "url": "https://x.com/udiWertheimer/status/2101093319501664368",
        "text": "you owe us a banked reset",
        "created_timestamp": 1_789_774_658,
        "author": ["screen_name": "udiWertheimer", "name": "Udi Wertheimer"],
        "quote": [
          "id": "2099744972195131850",
          "url": "https://x.com/thsottiaux/status/2099744972195131850",
          "text": "This week will also be a level of ships.",
          "created_timestamp": 1_789_453_187,
          "author": ["screen_name": "thsottiaux", "name": "Tibo"],
        ],
      ]
    ]
    ReplyContextURLProtocol.responseData = try JSONSerialization.data(withJSONObject: response)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ReplyContextURLProtocol.self]
    let client = PublicReplyContextClient(
      session: URLSession(configuration: configuration)
    )

    let fetchedContext = await client.fetchContext(
      parentTweetID: "2101093319501664368"
    )
    let context = try XCTUnwrap(fetchedContext?.objectValue)
    let parent = try XCTUnwrap(context.object("parent"))
    let quote = try XCTUnwrap(context.object("quoted_post"))

    XCTAssertEqual(parent.string("text"), "you owe us a banked reset")
    XCTAssertEqual(parent.string("author_handle"), "udiWertheimer")
    XCTAssertEqual(parent.string("at"), "2026-09-18T23:37:38Z")
    XCTAssertEqual(quote.string("text"), "This week will also be a level of ships.")
    XCTAssertEqual(quote.string("author_handle"), "thsottiaux")
  }

  func testFeedReplyIsEnrichedWithoutChangingTopLevelPost() async throws {
    let parentID = "2101093319501664368"
    let replyContext: JSONValue = .object([
      "parent": .object([
        "id": .string(parentID),
        "text": .string("you owe us a banked reset"),
      ])
    ])
    let feed: JSONValue = .object([
      "tweets": .array([
        .object([
          "id": .string("reply"),
          "text": .string("OK fine."),
          "is_reply": .bool(true),
          "in_reply_to_tweet_id": .string(parentID),
        ]),
        .object([
          "id": .string("top-level"),
          "text": .string("A standalone post"),
          "is_reply": .bool(false),
        ]),
      ])
    ])
    let cache = FileManager.default.temporaryDirectory
      .appendingPathComponent("TiboRadarReplyContextTest-\(UUID().uuidString)")
    let client = RadarClient(
      cacheDirectory: cache,
      replyContextClient: StubReplyContextClient(contexts: [parentID: replyContext])
    )

    let enriched = await client.enrichReplyContexts(in: feed)
    let tweets = try XCTUnwrap(enriched.objectValue?.array("tweets"))
    let reply = try XCTUnwrap(tweets[0].objectValue)
    let topLevel = try XCTUnwrap(tweets[1].objectValue)

    XCTAssertEqual(reply.object("reply_context"), replyContext.objectValue)
    XCTAssertNil(topLevel["reply_context"])
  }

  func testCachedReplyContextSurvivesTemporaryContextFetchFailure() async throws {
    let parentID = "2101093319501664368"
    let context: JSONValue = .object([
      "parent": .object(["text": .string("you owe us a banked reset")])
    ])
    let liveFeed: JSONValue = .object([
      "tweets": .array([
        .object([
          "id": .string("reply"),
          "is_reply": .bool(true),
          "in_reply_to_tweet_id": .string(parentID),
        ])
      ])
    ])
    let cachedFeed: JSONValue = .object([
      "tweets": .array([
        .object([
          "id": .string("reply"),
          "in_reply_to_tweet_id": .string(parentID),
          "reply_context": context,
        ])
      ])
    ])
    let cache = FileManager.default.temporaryDirectory
      .appendingPathComponent("TiboRadarReplyFallbackTest-\(UUID().uuidString)")
    let client = RadarClient(
      cacheDirectory: cache,
      replyContextClient: StubReplyContextClient(contexts: [:])
    )

    let enriched = await client.enrichReplyContexts(in: liveFeed, cachedFeed: cachedFeed)
    let reply = try XCTUnwrap(
      enriched.objectValue?.array("tweets")?.first?.objectValue
    )

    XCTAssertEqual(reply.object("reply_context"), context.objectValue)
  }
}
