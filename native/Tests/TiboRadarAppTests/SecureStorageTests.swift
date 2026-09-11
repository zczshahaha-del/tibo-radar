import Foundation
import XCTest

@testable import TiboRadarApp

final class SecureStorageTests: XCTestCase {
  func testKeychainRoundTripAndDelete() throws {
    let store = KeychainAPIKeyStore(
      service: "com.zc.tiboradar.tests.\(UUID().uuidString)"
    )
    defer { try? store.delete(for: .deepSeek) }

    XCTAssertNil(try store.read(for: .deepSeek))
    try store.save("test-only-not-a-real-key", for: .deepSeek)
    XCTAssertEqual(try store.read(for: .deepSeek), "test-only-not-a-real-key")
    try store.delete(for: .deepSeek)
    XCTAssertNil(try store.read(for: .deepSeek))
  }

  func testPreferencesContainModelButNeverAPIKey() {
    let suite = "TiboRadarPreferencesTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = ProviderPreferences(defaults: defaults)

    preferences.save(provider: .qwen, model: "qwen-plus")

    XCTAssertEqual(preferences.selectedProvider, .qwen)
    XCTAssertEqual(preferences.model(for: .qwen), "qwen-plus")
    let storedKeys = defaults.persistentDomain(forName: suite).map { Array($0.keys) } ?? []
    XCTAssertFalse(storedKeys.contains { $0.lowercased().contains("key") })
  }
}
