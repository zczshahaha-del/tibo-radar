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
  var posts: [String: JSONValue] = [:]

  func fetchContext(parentTweetID: String) async -> JSONValue? {
    contexts[parentTweetID]
  }
  func fetchPost(tweetID: String) async -> JSONValue? { posts[tweetID] }
}

final class RadarClientTests: XCTestCase {
  func testGeneralActivityWithoutReplyFieldsRecoversParentAndReusesCache() async throws {
    let context: JSONValue = .object([
      "parent": .object(["text": .string("What time is the product launch?")])
    ])
    let feed: JSONValue = .object([
      "radar_context": .array([.object([
        "id": .string("123"), "text": .string("Wednesday at 4am"),
        "visibility_only": .bool(true),
      ])])
    ])
    let cache = FileManager.default.temporaryDirectory
      .appendingPathComponent("TiboRadarReplyDiscovery-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: cache) }
    let client = RadarClient(cacheDirectory: cache, replyContextClient: StubReplyContextClient(
      contexts: ["456": context],
      posts: ["123": .object(["is_reply": .bool(true), "in_reply_to_tweet_id": .string("456")])]
    ))
    let result = await client.enrichReplyContexts(in: feed)
    let reply = try XCTUnwrap(result.objectValue?.array("radar_context")?.first?.objectValue)
    XCTAssertEqual(reply.string("text"), "Wednesday at 4am")
    XCTAssertEqual(reply.object("reply_context"), context.objectValue)
    XCTAssertEqual(reply.bool("is_reply"), true)

    let offline = RadarClient(cacheDirectory: cache, replyContextClient: StubReplyContextClient(contexts: [:]))
    let cached = await offline.enrichReplyContexts(in: feed, cachedFeed: result)
    XCTAssertEqual(cached, result)

    let unresolved = await offline.enrichReplyContexts(in: feed)
    let input = try AIInputBuilder.makeContext(bundle: SourceBundle(payloads: [.feed: unresolved], cacheFallbacks: [], errors: []))
    XCTAssertTrue(input.contains("\"reply_context_status\":\"unknown\""))
  }

  func testDiscoveredStandalonePostKeepsVerifiedNonReplyFlag() async throws {
    let cache = FileManager.default.temporaryDirectory
      .appendingPathComponent("TiboRadarNonReply-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: cache) }
    let client = RadarClient(cacheDirectory: cache, replyContextClient: StubReplyContextClient(
      contexts: [:], posts: ["123": .object(["is_reply": .bool(false)])]
    ))
    let result = await client.enrichReplyContexts(in: .object([
      "radar_context": .array([.object(["id": .string("123"), "text": .string("Hello")])])
    ]))
    XCTAssertEqual(result.objectValue?.array("radar_context")?.first?.objectValue?.bool("is_reply"), false)
  }

  func testPublicPostLookupParsesActualReplyFields() async throws {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [ReplyContextURLProtocol.self]
    let client = PublicReplyContextClient(session: URLSession(configuration: config))
    ReplyContextURLProtocol.responseData = Data("""
      {"tweet":{"id":"123","text":"Wednesday at 4am","replying_to":"someone","replying_to_status":"456"}}
      """.utf8)
    let post = await client.fetchPost(tweetID: "123")
    XCTAssertEqual(post?.objectValue?.string("in_reply_to_tweet_id"), "456")
    XCTAssertEqual(post?.objectValue?.bool("is_reply"), true)
    XCTAssertEqual(post?.objectValue?.string("replying_to"), "someone")
    let wrongPost = await client.fetchPost(tweetID: "999")
    XCTAssertNil(wrongPost)
    ReplyContextURLProtocol.responseData = Data("""
      {"tweet":{"id":"123","text":"Hello","replying_to_status":null}}
      """.utf8)
    let standalone = await client.fetchPost(tweetID: "123")
    XCTAssertEqual(standalone?.objectValue?.bool("is_reply"), false)
  }

  func testContextOnlyReplyReachesAIWithParentAndQuote() async throws {
    let context: JSONValue = .object([
      "parent": .object(["text": .string("What time is the product launch?")]),
      "quoted_post": .object(["text": .string("A new product is coming")]),
    ])
    let feed: JSONValue = .object([
      "radar_context": .array([
        .object([
          "id": .string("123"), "text": .string("3am on a tuesday"),
          "in_reply_to_tweet_id": .string("456"),
          "conversation_id": .string("456"), "visibility_only": .bool(true),
        ])
      ])
    ])
    let cache = FileManager.default.temporaryDirectory
      .appendingPathComponent("TiboRadarContextOnly-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: cache) }
    let client = RadarClient(
      cacheDirectory: cache,
      replyContextClient: StubReplyContextClient(contexts: ["456": context])
    )
    let enriched = await client.enrichReplyContexts(in: feed)
    let bundle = SourceBundle(payloads: [.feed: enriched], cacheFallbacks: [], errors: [])
    let input = try AIInputBuilder.makeContext(bundle: bundle)
    let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(input.utf8)) as? [String: Any])
    let post = try XCTUnwrap((root["recent_tibo_context"] as? [[String: Any]])?.first)
    XCTAssertEqual(post["reply_context_status"] as? String, "available")
    XCTAssertEqual(post["in_reply_to_tweet_id"] as? String, "456")
    XCTAssertEqual(post["conversation_id"] as? String, "456")
    XCTAssertTrue(input.contains("What time is the product launch?"))
    XCTAssertTrue(input.contains("A new product is coming"))
  }

  func testReplyContextCacheSurvivesMovingBetweenFeedLists() async throws {
    let context: JSONValue = .object([
      "parent": .object(["text": .string("you owe us a banked reset")])
    ])
    let cached: JSONValue = .object([
      "radar_context": .array([.object([
        "in_reply_to_tweet_id": .string("456"), "reply_context": context,
      ])])
    ])
    let feed: JSONValue = .object([
      "tweets": .array([.object([
        "id": .string("123"), "is_reply": .bool(true),
        "in_reply_to_tweet_id": .string("456"),
      ])])
    ])
    let cache = FileManager.default.temporaryDirectory
      .appendingPathComponent("TiboRadarCrossList-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: cache) }
    let client = RadarClient(cacheDirectory: cache, replyContextClient: StubReplyContextClient(contexts: [:]))
    let result = await client.enrichReplyContexts(in: feed, cachedFeed: cached)
    XCTAssertEqual(result.objectValue?.array("tweets")?.first?.objectValue?.object("reply_context"), context.objectValue)
  }

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
    XCTAssertTrue(bundle.receivedAt.isEmpty)
  }

  func testSuccessfulFetchRecordsReceiptTimeForSourcesWithoutTimestamps() async throws {
    ReplyContextURLProtocol.responseData = Data("{\"tweets\":[],\"incidents\":[]}".utf8)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ReplyContextURLProtocol.self]
    let cache = FileManager.default.temporaryDirectory
      .appendingPathComponent("TiboRadarReceiptTest-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: cache) }
    let bundle = await RadarClient(
      session: URLSession(configuration: configuration), cacheDirectory: cache
    ).fetchAll()
    XCTAssertEqual(bundle.receivedAt.count, RadarSource.allCases.count)
    XCTAssertTrue(SourceHealth.assess(bundle: bundle).allSatisfy { $0.state == .fresh })
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
