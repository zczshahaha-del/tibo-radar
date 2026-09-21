import Foundation

private struct FetchResult: Sendable {
  let source: RadarSource
  let payload: JSONValue?
  let usedCache: Bool
  let error: String?
}

final class RadarClient: @unchecked Sendable {
  private let session: URLSession
  private let cacheDirectory: URL
  private let replyContextClient: any ReplyContextFetching

  init(
    session: URLSession = .shared,
    cacheDirectory: URL? = nil,
    replyContextClient: (any ReplyContextFetching)? = nil
  ) {
    self.session = session
    self.replyContextClient = replyContextClient ?? PublicReplyContextClient(session: session)
    if let cacheDirectory {
      self.cacheDirectory = cacheDirectory
    } else {
      let base = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first!
      self.cacheDirectory =
        base
        .appendingPathComponent("TiboRadar", isDirectory: true)
        .appendingPathComponent("cache", isDirectory: true)
    }
    try? FileManager.default.createDirectory(
      at: self.cacheDirectory,
      withIntermediateDirectories: true
    )
  }

  func fetchAll() async -> SourceBundle {
    await withTaskGroup(of: FetchResult.self) { group in
      for source in RadarSource.allCases {
        group.addTask { [self] in
          await fetch(source)
        }
      }

      var payloads: [RadarSource: JSONValue] = [:]
      var cacheFallbacks = Set<RadarSource>()
      var errors: [String] = []
      for await result in group {
        if let payload = result.payload {
          payloads[result.source] = payload
        }
        if result.usedCache {
          cacheFallbacks.insert(result.source)
        }
        if let error = result.error {
          errors.append(error)
        }
      }

      if let feed = payloads[.feed], !cacheFallbacks.contains(.feed) {
        let enrichedFeed = await enrichReplyContexts(
          in: feed,
          cachedFeed: readCache(for: .feed)
        )
        payloads[.feed] = enrichedFeed
        try? JSONEncoder().encode(enrichedFeed).write(
          to: cacheURL(for: .feed),
          options: .atomic
        )
      }
      return SourceBundle(
        payloads: payloads,
        cacheFallbacks: cacheFallbacks,
        errors: errors.sorted()
      )
    }
  }

  private func fetch(_ source: RadarSource) async -> FetchResult {
    var request = URLRequest(url: source.url)
    request.timeoutInterval = 12
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue(
      "TiboRadar/0.2 (+native personal monitor)",
      forHTTPHeaderField: "User-Agent"
    )

    do {
      let (data, response) = try await session.data(for: request)
      guard let http = response as? HTTPURLResponse,
        (200...299).contains(http.statusCode)
      else {
        throw URLError(.badServerResponse)
      }
      let payload = try JSONDecoder().decode(JSONValue.self, from: data)
      guard payload.objectValue != nil else {
        throw URLError(.cannotParseResponse)
      }
      if source != .feed {
        try? JSONEncoder().encode(payload).write(to: cacheURL(for: source), options: .atomic)
      }
      return FetchResult(source: source, payload: payload, usedCache: false, error: nil)
    } catch {
      if let cached = readCache(for: source) {
        return FetchResult(
          source: source,
          payload: cached,
          usedCache: true,
          error: "\(source.rawValue)：网络失败，正在使用缓存"
        )
      }
      return FetchResult(
        source: source,
        payload: nil,
        usedCache: false,
        error: "\(source.rawValue)：无法获取且没有缓存"
      )
    }
  }

  private func cacheURL(for source: RadarSource) -> URL {
    cacheDirectory.appendingPathComponent("\(source.rawValue).json")
  }

  private func readCache(for source: RadarSource) -> JSONValue? {
    guard let data = try? Data(contentsOf: cacheURL(for: source)) else { return nil }
    return try? JSONDecoder().decode(JSONValue.self, from: data)
  }

  func enrichReplyContexts(
    in feed: JSONValue,
    cachedFeed: JSONValue? = nil
  ) async -> JSONValue {
    guard var feedObject = feed.objectValue,
      let tweets = feedObject.array("tweets")
    else { return feed }

    let parentIDs = tweets.prefix(12).compactMap { value -> String? in
      guard let tweet = value.objectValue,
        tweet.bool("is_reply") == true
      else { return nil }
      return tweet.string("in_reply_to_tweet_id")
    }
    let uniqueParentIDs = Array(Set(parentIDs)).sorted()
    guard !uniqueParentIDs.isEmpty else { return feed }

    let cachedContexts = Self.cachedReplyContexts(from: cachedFeed)
    let parentIDSet = Set(uniqueParentIDs)
    var fetchedContexts = cachedContexts.filter { parentIDSet.contains($0.key) }
    let missingParentIDs = uniqueParentIDs.filter { cachedContexts[$0] == nil }
    let client = replyContextClient
    await withTaskGroup(of: (String, JSONValue?).self) { group in
      for parentID in missingParentIDs {
        group.addTask {
          (parentID, await client.fetchContext(parentTweetID: parentID))
        }
      }
      for await (parentID, context) in group {
        if let context {
          fetchedContexts[parentID] = context
        }
      }
    }

    feedObject["tweets"] = .array(tweets.map { value in
      guard var tweet = value.objectValue,
        let parentID = tweet.string("in_reply_to_tweet_id"),
        let context = fetchedContexts[parentID]
      else { return value }
      tweet["reply_context"] = context
      return .object(tweet)
    })
    return .object(feedObject)
  }

  private static func cachedReplyContexts(from feed: JSONValue?) -> [String: JSONValue] {
    guard let tweets = feed?.objectValue?.array("tweets") else { return [:] }
    var contexts: [String: JSONValue] = [:]
    for value in tweets {
      guard let tweet = value.objectValue,
        let parentID = tweet.string("in_reply_to_tweet_id"),
        let context = tweet["reply_context"]
      else { continue }
      contexts[parentID] = context
    }
    return contexts
  }
}
