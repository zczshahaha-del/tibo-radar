import Foundation

private struct CachedAISnapshot: Codable {
  let version: Int
  let provider: AIProvider
  let model: String
  let snapshot: PredictionSnapshot
}

final class AISnapshotStore: @unchecked Sendable {
  private let directory: URL

  init(directory: URL? = nil) {
    if let directory {
      self.directory = directory
    } else {
      let base = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first!
      self.directory = base
        .appendingPathComponent("TiboRadar", isDirectory: true)
        .appendingPathComponent("ai-snapshots", isDirectory: true)
    }
    try? FileManager.default.createDirectory(
      at: self.directory,
      withIntermediateDirectories: true
    )
  }

  func save(
    _ snapshot: PredictionSnapshot,
    configuration: AIConfiguration
  ) throws {
    let cached = CachedAISnapshot(
      version: 5,
      provider: configuration.provider,
      model: configuration.model,
      snapshot: snapshot
    )
    let data = try JSONEncoder().encode(cached)
    try data.write(to: url(for: configuration.provider), options: .atomic)
  }

  func load(for provider: AIProvider) -> PredictionSnapshot? {
    guard let data = try? Data(contentsOf: url(for: provider)),
      let cached = try? JSONDecoder().decode(CachedAISnapshot.self, from: data),
      cached.version == 5,
      cached.provider == provider
    else { return nil }
    return cached.snapshot
  }

  private func url(for provider: AIProvider) -> URL {
    directory.appendingPathComponent("\(provider.rawValue).json")
  }
}
