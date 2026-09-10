import Foundation
import SwiftUI

@MainActor
final class RadarViewModel: ObservableObject {
  @Published private(set) var snapshot: PredictionSnapshot?
  @Published private(set) var isRefreshing = false
  @Published private(set) var isTestingConnection = false
  @Published private(set) var lastError: String?
  @Published private(set) var settingsMessage: String?
  @Published private(set) var selectedProvider: AIProvider
  @Published private(set) var selectedModel: String
  @Published private(set) var hasAPIKey: Bool

  private let client: RadarClient
  private let analyzer: any AIAnalyzing
  private let credentials: any APIKeyStoring
  private let preferences: ProviderPreferences
  private let snapshotStore: AISnapshotStore
  private let refreshGate: AIRefreshGate
  private let notifications: NotificationManager
  private var refreshTimer: Timer?

  init(
    client: RadarClient = RadarClient(),
    analyzer: any AIAnalyzing = AIProviderClient(),
    credentials: any APIKeyStoring = KeychainAPIKeyStore(),
    preferences: ProviderPreferences = ProviderPreferences(),
    snapshotStore: AISnapshotStore = AISnapshotStore(),
    refreshGate: AIRefreshGate = AIRefreshGate(),
    notifications: NotificationManager = NotificationManager()
  ) {
    self.client = client
    self.analyzer = analyzer
    self.credentials = credentials
    self.preferences = preferences
    self.snapshotStore = snapshotStore
    self.refreshGate = refreshGate
    self.notifications = notifications

    let provider = preferences.selectedProvider
    selectedProvider = provider
    selectedModel = preferences.model(for: provider)
    hasAPIKey = (try? credentials.read(for: provider)) != nil
    snapshot = snapshotStore.load(for: provider)

    if !hasAPIKey {
      lastError = "请先点右上角齿轮，选择模型并填写自己的 API Key。"
      snapshot = snapshot?.markedStale(reason: "当前没有可用的 API Key，显示的是上次 AI 结果。")
    }

    Task { [weak self] in
      guard let self, self.hasAPIKey else { return }
      await self.notifications.prepareAuthorization()
      await self.refresh(force: false)
    }
    refreshTimer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) {
      [weak self] _ in
      Task { @MainActor [weak self] in
        guard self?.hasAPIKey == true else { return }
        await self?.refresh(force: false)
      }
    }
  }

  init(previewSnapshot: PredictionSnapshot) {
    snapshot = previewSnapshot
    isRefreshing = false
    isTestingConnection = false
    lastError = nil
    settingsMessage = nil
    selectedProvider = .qwen
    selectedModel = AIProvider.qwen.defaultModel
    hasAPIKey = true
    client = RadarClient()
    analyzer = AIProviderClient()
    credentials = KeychainAPIKeyStore()
    preferences = ProviderPreferences()
    snapshotStore = AISnapshotStore()
    refreshGate = AIRefreshGate()
    notifications = NotificationManager()
  }

  func refresh(force: Bool = true) async {
    guard !isRefreshing else { return }
    guard let apiKey = try? credentials.read(for: selectedProvider), !apiKey.isEmpty else {
      hasAPIKey = false
      lastError = "还没有 \(selectedProvider.displayName) API Key，请先打开设置。"
      snapshot = snapshotStore.load(for: selectedProvider)?.markedStale(
        reason: "缺少 API Key，无法生成新的 AI 判断。"
      )
      return
    }

    isRefreshing = true
    lastError = nil
    defer { isRefreshing = false }

    let configuration = AIConfiguration(
      provider: selectedProvider,
      model: selectedModel
    )
    let bundle = await client.fetchAll()

    do {
      if selectedProvider == .deepSeek, bundle.payloads.isEmpty {
        throw AIProviderError.invalidAnalysis("没有获取到可供 DeepSeek 判断的公开资料。")
      }
      let context = try AIInputBuilder.makeContext(bundle: bundle)
      let fingerprint = try AIInputBuilder.fingerprint(bundle: bundle)
      if !refreshGate.shouldAnalyze(
        configuration: configuration,
        sourceFingerprint: fingerprint,
        force: force
      ), let cached = snapshotStore.load(for: selectedProvider) {
        snapshot = cached
        return
      }
      let analysis = try await analyzer.analyze(
        context: context,
        configuration: configuration,
        apiKey: apiKey
      )
      let next = analysis.snapshot(bundle: bundle)
      snapshot = next
      try snapshotStore.save(next, configuration: configuration)
      refreshGate.recordSuccess(
        configuration: configuration,
        sourceFingerprint: fingerprint
      )
      await notifications.process(next)
    } catch {
      let message = Self.displayMessage(for: error)
      lastError = message
      if let cached = snapshotStore.load(for: selectedProvider) {
        snapshot = cached.markedStale(reason: "AI 刷新失败：\(message)")
      } else {
        snapshot = nil
      }
    }
  }

  func useProvider(_ provider: AIProvider) {
    selectedProvider = provider
    selectedModel = preferences.model(for: provider)
    hasAPIKey = (try? credentials.read(for: provider)) != nil
    preferences.selectedProvider = provider
    snapshot = snapshotStore.load(for: provider)
    lastError = hasAPIKey ? nil : "还没有 \(provider.displayName) API Key。"
    settingsMessage = nil
  }

  func modelName(for provider: AIProvider) -> String {
    preferences.model(for: provider)
  }

  func keyIsSaved(for provider: AIProvider) -> Bool {
    (try? credentials.read(for: provider)) != nil
  }

  @discardableResult
  func saveSettings(
    provider: AIProvider,
    model: String,
    newAPIKey: String
  ) -> Bool {
    do {
      let cleanedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
      preferences.save(provider: provider, model: cleanedModel)
      let cleanedKey = newAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
      if !cleanedKey.isEmpty {
        try credentials.save(cleanedKey, for: provider)
      } else if (try credentials.read(for: provider)) == nil {
        throw APIKeyStoreError.emptyKey
      }
      useProvider(provider)
      selectedModel = preferences.model(for: provider)
      hasAPIKey = true
      lastError = nil
      settingsMessage = "已保存到 macOS 钥匙串。"
      return true
    } catch {
      settingsMessage = Self.displayMessage(for: error)
      return false
    }
  }

  func saveAndTest(
    provider: AIProvider,
    model: String,
    newAPIKey: String
  ) async {
    guard saveSettings(provider: provider, model: model, newAPIKey: newAPIKey)
    else { return }
    guard let key = try? credentials.read(for: provider) else {
      settingsMessage = "无法从 macOS 钥匙串读取 API Key。"
      return
    }

    isTestingConnection = true
    settingsMessage = "正在连接 \(provider.displayName)…"
    defer { isTestingConnection = false }
    do {
      try await analyzer.testConnection(
        configuration: AIConfiguration(provider: provider, model: selectedModel),
        apiKey: key
      )
      settingsMessage = "连接成功，可以生成 AI 预测。"
    } catch {
      settingsMessage = Self.displayMessage(for: error)
    }
  }

  func deleteAPIKey(for provider: AIProvider) {
    do {
      try credentials.delete(for: provider)
      if selectedProvider == provider {
        hasAPIKey = false
        lastError = "已删除 \(provider.displayName) API Key。"
      }
      settingsMessage = "已从 macOS 钥匙串删除。"
    } catch {
      settingsMessage = Self.displayMessage(for: error)
    }
  }

  private static func displayMessage(for error: Error) -> String {
    if let localized = error as? LocalizedError,
      let description = localized.errorDescription
    {
      return description
    }
    if let urlError = error as? URLError {
      switch urlError.code {
      case .notConnectedToInternet:
        return "当前没有网络连接。"
      case .timedOut:
        return "模型请求超时，请稍后重试。"
      default:
        return "网络请求失败：\(urlError.localizedDescription)"
      }
    }
    return error.localizedDescription
  }
}
