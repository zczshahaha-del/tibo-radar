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

  init(session: URLSession = .shared, cacheDirectory: URL? = nil) {
    self.session = session
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
      try? JSONEncoder().encode(payload).write(to: cacheURL(for: source), options: .atomic)
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
}
