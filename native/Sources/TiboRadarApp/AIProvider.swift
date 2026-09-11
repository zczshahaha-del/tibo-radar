import Foundation

enum AIProvider: String, CaseIterable, Codable, Identifiable, Sendable {
  case deepSeek = "deepseek"
  case qwen

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .deepSeek: "DeepSeek"
    case .qwen: "千问"
    }
  }

  var defaultModel: String {
    switch self {
    case .deepSeek: "deepseek-flash"
    case .qwen: "qwen-plus"
    }
  }

  var endpoint: URL {
    switch self {
    case .deepSeek:
      URL(string: "https://api.deepseek.com/chat/completions")!
    case .qwen:
      URL(
        string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
      )!
    }
  }

  var capabilityNote: String {
    switch self {
    case .deepSeek:
      "分析 App 采集的 Tibo、历史事件和官方状态原文。"
    case .qwen:
      "除 App 采集的原文外，还会启用百炼联网搜索。"
    }
  }
}

struct AIConfiguration: Equatable, Sendable {
  let provider: AIProvider
  let model: String
}

final class ProviderPreferences: @unchecked Sendable {
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  var selectedProvider: AIProvider {
    get {
      guard let raw = defaults.string(forKey: "ai.selectedProvider"),
        let provider = AIProvider(rawValue: raw)
      else { return .deepSeek }
      return provider
    }
    set {
      defaults.set(newValue.rawValue, forKey: "ai.selectedProvider")
    }
  }

  func model(for provider: AIProvider) -> String {
    let saved = defaults.string(forKey: "ai.model.\(provider.rawValue)")?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return saved?.isEmpty == false ? saved! : provider.defaultModel
  }

  func save(provider: AIProvider, model: String) {
    selectedProvider = provider
    let cleaned = model.trimmingCharacters(in: .whitespacesAndNewlines)
    defaults.set(
      cleaned.isEmpty ? provider.defaultModel : cleaned,
      forKey: "ai.model.\(provider.rawValue)"
    )
  }
}
