import Foundation

protocol ReplyContextFetching: Sendable {
  func fetchContext(parentTweetID: String) async -> JSONValue?
}

final class PublicReplyContextClient: ReplyContextFetching, @unchecked Sendable {
  private let session: URLSession

  init(session: URLSession = .shared) {
    self.session = session
  }

  func fetchContext(parentTweetID: String) async -> JSONValue? {
    guard Self.isValidTweetID(parentTweetID) else { return nil }
    let baseURL = URL(string: "https://api.fxtwitter.com/status")!
    let url = baseURL.appendingPathComponent(parentTweetID)
    var request = URLRequest(url: url)
    request.timeoutInterval = 8
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue(
      "TiboRadar/0.2 (+public reply context)",
      forHTTPHeaderField: "User-Agent"
    )

    do {
      let (data, response) = try await session.data(for: request)
      guard let http = response as? HTTPURLResponse,
        (200...299).contains(http.statusCode),
        let root = try JSONDecoder().decode(JSONValue.self, from: data).objectValue,
        let tweet = root.object("tweet"),
        let parent = Self.normalizedPost(tweet)
      else { return nil }

      var context: [String: JSONValue] = [
        "parent": parent,
        "source": .string("api.fxtwitter.com"),
      ]
      if let quote = tweet.object("quote"),
        let normalizedQuote = Self.normalizedPost(quote)
      {
        context["quoted_post"] = normalizedQuote
      }
      return .object(context)
    } catch {
      return nil
    }
  }

  private static func normalizedPost(_ post: [String: JSONValue]) -> JSONValue? {
    guard let id = post.string("id"),
      let text = post.string("text"),
      !text.isEmpty
    else { return nil }

    var result: [String: JSONValue] = [
      "id": .string(id),
      "text": .string(text),
    ]
    if let url = post.string("url"), !url.isEmpty {
      result["url"] = .string(url)
    }
    if let timestamp = post.number("created_timestamp") {
      result["at"] = .string(
        ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: timestamp))
      )
    } else if let createdAt = post.string("created_at"), !createdAt.isEmpty {
      result["at"] = .string(createdAt)
    }
    if let author = post.object("author") {
      if let handle = author.string("screen_name"), !handle.isEmpty {
        result["author_handle"] = .string(handle)
      }
      if let name = author.string("name"), !name.isEmpty {
        result["author_name"] = .string(name)
      }
    }
    return .object(result)
  }

  private static func isValidTweetID(_ value: String) -> Bool {
    (1...24).contains(value.count) && value.allSatisfy(\.isNumber)
  }
}
