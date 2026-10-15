import Foundation

struct RadarHistoryEntry: Codable, Equatable, Sendable {
  enum Event: String, Codable, Sendable {
    case startup, providerChanged, refreshSucceeded, refreshReused, refreshFailed
  }

  let recordedAt: Date
  let provider: AIProvider
  let model: String
  let event: Event
  let color: RadarIndicatorLevel
  let snapshot: PredictionSnapshot?
  let error: String?
}

@MainActor
final class RadarHistoryStore {
  private struct Archive: Codable {
    let version: Int
    let entries: [RadarHistoryEntry]
  }

  private let url: URL
  private let retention: TimeInterval
  private let maximumEntries: Int

  init(
    directory: URL? = nil,
    retention: TimeInterval = 30 * 86_400,
    maximumEntries: Int = 1_000
  ) {
    let base = directory ?? FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask
    ).first!.appendingPathComponent("TiboRadar/history", isDirectory: true)
    url = base.appendingPathComponent("predictions.json")
    self.retention = max(0, retention)
    self.maximumEntries = max(1, maximumEntries)
  }

  func load() throws -> [RadarHistoryEntry] {
    guard FileManager.default.fileExists(atPath: url.path) else { return [] }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let archive = try decoder.decode(Archive.self, from: Data(contentsOf: url))
    guard archive.version == 1 else {
      throw CocoaError(.coderReadCorrupt)
    }
    return archive.entries
  }

  func record(
    event: RadarHistoryEntry.Event,
    configuration: AIConfiguration,
    snapshot: PredictionSnapshot?,
    error: String? = nil,
    now: Date = Date()
  ) throws {
    let entry = RadarHistoryEntry(
      recordedAt: now, provider: configuration.provider, model: configuration.model,
      event: event, color: RadarIndicatorState(snapshot: snapshot).level,
      snapshot: snapshot, error: error
    )
    var entries = try load().filter { $0.recordedAt >= now.addingTimeInterval(-retention) }
    entries.append(entry)
    entries = Array(entries.sorted { $0.recordedAt < $1.recordedAt }.suffix(maximumEntries))
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(Archive(version: 1, entries: entries))
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
  }
}
