import Foundation
import XCTest

@testable import TiboRadarApp

private final class ViewModelResponses: @unchecked Sendable {
  private let lock = NSLock()
  private var feedData: Data?
  func setFeed(_ data: Data?) {
    lock.lock()
    defer { lock.unlock() }
    feedData = data
  }
  func feed() -> Data? {
    lock.lock()
    defer { lock.unlock() }
    return feedData
  }
}

private final class ViewModelURLProtocol: URLProtocol, @unchecked Sendable {
  static let responses = ViewModelResponses()
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    let data = request.url == RadarSource.feed.url ? Self.responses.feed() : nil
    client?.urlProtocol(self, didLoad: data ?? Data("{}".utf8))
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

private final class ViewModelKeys: APIKeyStoring, @unchecked Sendable {
  var keys: [AIProvider: String] = [.deepSeek: "fake", .qwen: "fake"]
  var rejectSave = false
  func read(for provider: AIProvider) throws -> String? { keys[provider] }
  func save(_ key: String, for provider: AIProvider) throws {
    if rejectSave { throw APIKeyStoreError.emptyKey }
    keys[provider] = key
  }
  func delete(for provider: AIProvider) throws { keys.removeValue(forKey: provider) }
}

private actor SuspendedAnalyzer: AIAnalyzing {
  var automaticAnalysis: AIAnalysis?
  var pending: [CheckedContinuation<AIAnalysis, Error>] = []
  var requestCount = 0
  var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
  func analyze(context: String, configuration: AIConfiguration, apiKey: String) async throws -> AIAnalysis {
    if let automaticAnalysis {
      requestCount += 1
      return automaticAnalysis
    }
    return try await withCheckedThrowingContinuation { continuation in
      pending.append(continuation)
      requestCount += 1
      waiters.filter { $0.0 <= requestCount }.forEach { $0.1.resume() }
      waiters.removeAll { $0.0 <= requestCount }
    }
  }
  func waitForRequest(count: Int = 1) async {
    if requestCount >= count { return }
    await withCheckedContinuation { waiters.append((count, $0)) }
  }
  func finish(_ result: Result<AIAnalysis, Error>) { pending.removeFirst().resume(with: result) }
  func respondAutomatically(with analysis: AIAnalysis) { automaticAnalysis = analysis }
  func testConnection(configuration: AIConfiguration, apiKey: String) async throws {}
}

final class RadarViewModelTests: XCTestCase {
  @MainActor
  private func fixture(history: RadarHistoryStore? = nil) throws -> (
    RadarViewModel, SuspendedAnalyzer, ViewModelKeys, ProviderPreferences, AISnapshotStore, () -> Void
  ) {
    let suite = "TiboRadar.viewmodel-test.\(UUID().uuidString)"
    ViewModelURLProtocol.responses.setFeed(nil)
    let defaults = UserDefaults(suiteName: suite)!
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ViewModelURLProtocol.self]
    let client = RadarClient(session: URLSession(configuration: configuration), cacheDirectory: root.appendingPathComponent("sources"))
    let analyzer = SuspendedAnalyzer()
    let keys = ViewModelKeys()
    let preferences = ProviderPreferences(defaults: defaults)
    let store = AISnapshotStore(directory: root.appendingPathComponent("snapshots"))
    let model = RadarViewModel(client: client, analyzer: analyzer, credentials: keys,
      preferences: preferences, snapshotStore: store,
      historyStore: history ?? RadarHistoryStore(directory: root.appendingPathComponent("history")),
      refreshGate: AIRefreshGate(defaults: defaults),
      notifications: NotificationManager(defaults: UserDefaults(suiteName: suite)!), startAutomatically: false)
    return (model, analyzer, keys, preferences, store, {
      defaults.removePersistentDomain(forName: suite)
      try? FileManager.default.removeItem(at: root)
    })
  }

  @MainActor
  func testFrequentChecksSkipChatterButAnalyzeAnImportantPostImmediately() async throws {
    let (model, analyzer, _, _, _, cleanup) = try fixture()
    defer { cleanup() }
    await analyzer.respondAutomatically(with: analysis())
    await model.refresh(force: false)
    let firstCount = await analyzer.requestCount
    XCTAssertEqual(firstCount, 1)
    let chatter: JSONValue = .object(["radar_context": .array([.object([
      "id": .string("smalltalk"), "text": .string("Thanks!"), "is_reply": .bool(true),
      "in_reply_to_tweet_id": .string("parent"),
      "reply_context": .object(["parent": .object(["text": .string("Nice wallpaper")])]),
    ])])])
    // Empty arrays and an empty feed describe the same lack of important content.
    ViewModelURLProtocol.responses.setFeed(try JSONEncoder().encode(chatter))
    await model.refresh(force: false)
    let chatterCount = await analyzer.requestCount
    XCTAssertEqual(chatterCount, 1)
    let reset: JSONValue = .object(["radar_context": .array([.object([
      "id": .string("announcement"), "text": .string("Loading a banked reset for everyone"),
      "is_reply": .bool(false),
    ])])])
    ViewModelURLProtocol.responses.setFeed(try JSONEncoder().encode(reset))
    await model.refresh(force: false)
    let importantCount = await analyzer.requestCount
    XCTAssertEqual(importantCount, 2)
    await model.refresh(force: false)
    let duplicateCount = await analyzer.requestCount
    XCTAssertEqual(duplicateCount, 2)
    await model.refresh()
    let forcedCount = await analyzer.requestCount
    XCTAssertEqual(forcedCount, 3)
  }

  @MainActor
  func testUnchangedAutomaticRefreshReusesPredictionAndRecordsHistory() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let history = RadarHistoryStore(directory: directory)
    let (model, analyzer, _, _, _, cleanup) = try fixture(history: history)
    defer { cleanup() }
    let task = Task { await model.refresh() }
    await analyzer.waitForRequest()
    await analyzer.finish(.success(analysis()))
    await task.value
    let generatedAt = model.snapshot?.generatedAt
    await model.refresh(force: false)
    XCTAssertEqual(model.snapshot?.generatedAt, generatedAt)
    XCTAssertEqual(try history.load().map(\.event), [.startup, .refreshSucceeded])
  }

  @MainActor
  func testHistoryRecordsStartupSuccessAndFailureWithDisplayedResult() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let history = RadarHistoryStore(directory: directory)
    let (model, analyzer, _, _, _, cleanup) = try fixture(history: history)
    defer { cleanup() }
    let success = Task { await model.refresh() }
    await analyzer.waitForRequest()
    await analyzer.finish(.success(analysis()))
    await success.value
    let failure = Task { await model.refresh() }
    await analyzer.waitForRequest(count: 2)
    await analyzer.finish(.failure(AIProviderError.unauthorized))
    await failure.value
    let entries = try history.load()
    XCTAssertEqual(entries.map(\.event), [.startup, .refreshSucceeded, .refreshFailed])
    XCTAssertEqual(entries.map(\.color), [.unavailable, .low, .low])
    XCTAssertEqual(entries.last?.snapshot?.combined24h.likely, 10)
    XCTAssertEqual(entries.last?.snapshot?.isStale, true)
    XCTAssertNotNil(entries.last?.error)
  }

  @MainActor
  func testObsoleteRequestDoesNotEnterHistory() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let history = RadarHistoryStore(directory: directory)
    let (model, analyzer, _, _, _, cleanup) = try fixture(history: history)
    defer { cleanup() }
    let task = Task { await model.refresh() }
    await analyzer.waitForRequest()
    model.useProvider(.qwen)
    await analyzer.finish(.success(analysis()))
    await task.value
    let entries = try history.load()
    XCTAssertEqual(entries.map(\.event), [.startup, .providerChanged])
    XCTAssertEqual(entries.map(\.provider), [.deepSeek, .qwen])
  }

  @MainActor
  func testHistoryWriteFailureDoesNotDiscardSuccessfulPrediction() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("file")
    try Data().write(to: file)
    let history = RadarHistoryStore(directory: file)
    let (model, analyzer, _, _, _, cleanup) = try fixture(history: history)
    defer { cleanup() }
    let task = Task { await model.refresh() }
    await analyzer.waitForRequest()
    await analyzer.finish(.success(analysis()))
    await task.value
    XCTAssertEqual(model.snapshot?.combined24h.likely, 10)
    XCTAssertNil(model.lastError)
  }

  @MainActor
  func testOldProviderSuccessCannotReplaceNewProviderSnapshot() async throws {
    let (model, analyzer, _, _, store, cleanup) = try fixture()
    defer { cleanup() }
    let task = Task { await model.refresh() }
    await analyzer.waitForRequest()
    model.useProvider(.qwen)
    await analyzer.finish(.success(analysis()))
    await task.value
    XCTAssertEqual(model.selectedProvider, .qwen)
    XCTAssertNil(model.snapshot)
    XCTAssertNil(store.load(for: .qwen))
    XCTAssertFalse(model.isRefreshing)
  }

  @MainActor
  func testOldProviderFailureCannotSetNewProviderError() async throws {
    let (model, analyzer, _, _, _, cleanup) = try fixture()
    defer { cleanup() }
    let task = Task { await model.refresh() }
    await analyzer.waitForRequest()
    model.useProvider(.qwen)
    await analyzer.finish(.failure(AIProviderError.unauthorized))
    await task.value
    XCTAssertNil(model.lastError)
    XCTAssertFalse(model.isRefreshing)
  }

  @MainActor
  func testSwitchingAwayAndBackStillDiscardsOldRequest() async throws {
    let (model, analyzer, _, _, _, cleanup) = try fixture()
    defer { cleanup() }
    let task = Task { await model.refresh() }
    await analyzer.waitForRequest()
    model.useProvider(.qwen)
    model.useProvider(.deepSeek)
    await analyzer.finish(.success(analysis()))
    await task.value
    XCTAssertNil(model.snapshot)
  }

  @MainActor
  func testNewRefreshCanStartAndOldCompletionCannotClearItsBusyState() async throws {
    let (model, analyzer, _, _, store, cleanup) = try fixture()
    defer { cleanup() }
    let oldTask = Task { await model.refresh() }
    await analyzer.waitForRequest()
    model.useProvider(.qwen)
    XCTAssertFalse(model.isRefreshing)
    let newTask = Task { await model.refresh() }
    await analyzer.waitForRequest(count: 2)
    await analyzer.finish(.success(analysis()))
    await oldTask.value
    XCTAssertTrue(model.isRefreshing)
    XCTAssertNil(model.snapshot)
    XCTAssertNil(store.load(for: .deepSeek))
    await analyzer.finish(.success(analysis()))
    await newTask.value
    XCTAssertFalse(model.isRefreshing)
    XCTAssertEqual(model.snapshot?.combined24h.likely, 10)
    XCTAssertEqual(store.load(for: .qwen)?.combined24h.likely, 10)
  }

  @MainActor
  func testSavingModelOrDeletingKeyInvalidatesPendingRefresh() async throws {
    for deleteKey in [false, true] {
      let (model, analyzer, _, _, _, cleanup) = try fixture()
      defer { cleanup() }
      let task = Task { await model.refresh() }
      await analyzer.waitForRequest()
      if deleteKey {
        model.deleteAPIKey(for: .deepSeek)
      } else {
        XCTAssertTrue(model.saveSettings(provider: .deepSeek, model: "changed", newAPIKey: ""))
      }
      await analyzer.finish(.success(analysis()))
      await task.value
      XCTAssertNil(model.snapshot)
      XCTAssertFalse(model.isRefreshing)
    }
  }

  @MainActor
  func testMissingKeyDoesNotPersistFailedSettings() throws {
    let (model, _, keys, preferences, _, cleanup) = try fixture()
    defer { cleanup() }
    keys.keys.removeValue(forKey: .qwen)
    XCTAssertFalse(model.saveSettings(provider: .qwen, model: "changed", newAPIKey: ""))
    XCTAssertEqual(preferences.selectedProvider, .deepSeek)
    XCTAssertEqual(preferences.model(for: .qwen), AIProvider.qwen.defaultModel)
    XCTAssertEqual(model.selectedProvider, .deepSeek)
  }

  @MainActor
  func testKeychainFailureDoesNotPersistSettingsAndSuccessfulSaveDoes() throws {
    let (model, _, keys, preferences, _, cleanup) = try fixture()
    defer { cleanup() }
    keys.rejectSave = true
    XCTAssertFalse(model.saveSettings(provider: .qwen, model: "changed", newAPIKey: "new-key"))
    XCTAssertEqual(preferences.selectedProvider, .deepSeek)
    XCTAssertEqual(preferences.model(for: .qwen), AIProvider.qwen.defaultModel)
    keys.rejectSave = false
    XCTAssertTrue(model.saveSettings(provider: .qwen, model: "changed", newAPIKey: "new-key"))
    XCTAssertEqual(preferences.selectedProvider, .qwen)
    XCTAssertEqual(model.selectedModel, "changed")
    XCTAssertEqual(keys.keys[.qwen], "new-key")
  }

  private func analysis() -> AIAnalysis {
    let range = ForecastProbabilityRange(lower: 5, likely: 10, upper: 15)
    return AIAnalysis(global24h: range, global48h: range, banked24h: range, banked48h: range,
      combined24h: range, combined48h: range, affectedUserBanked24h: nil, usageAdvice: .watch,
      analysisNote: "test", conditionalWindow: "unknown", summary: "test", evidence: [])
  }
}
