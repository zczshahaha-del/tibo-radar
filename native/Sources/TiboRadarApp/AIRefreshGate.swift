import Foundation

enum AIRefreshSchedule {
  static let automaticInterval: TimeInterval = 2 * 60 * 60
  static let label = "2 小时巡检"
}

final class AIRefreshGate: @unchecked Sendable {
  private let defaults: UserDefaults
  private let minimumPeriodicInterval: TimeInterval

  init(
    defaults: UserDefaults = .standard,
    minimumPeriodicInterval: TimeInterval = AIRefreshSchedule.automaticInterval
  ) {
    self.defaults = defaults
    self.minimumPeriodicInterval = minimumPeriodicInterval
  }

  func shouldAnalyze(
    configuration: AIConfiguration,
    sourceFingerprint: String,
    now: Date = Date(),
    force: Bool
  ) -> Bool {
    if force { return true }
    let prefix = keyPrefix(for: configuration)
    guard let previous = defaults.string(forKey: "\(prefix).fingerprint"),
      let lastSuccess = defaults.object(forKey: "\(prefix).lastSuccess") as? Date
    else { return true }
    if previous != sourceFingerprint { return true }
    return now.timeIntervalSince(lastSuccess) >= minimumPeriodicInterval
  }

  func recordSuccess(
    configuration: AIConfiguration,
    sourceFingerprint: String,
    now: Date = Date()
  ) {
    let prefix = keyPrefix(for: configuration)
    defaults.set(sourceFingerprint, forKey: "\(prefix).fingerprint")
    defaults.set(now, forKey: "\(prefix).lastSuccess")
  }

  private func keyPrefix(for configuration: AIConfiguration) -> String {
    let safeModel = configuration.model
      .replacingOccurrences(of: ".", with: "_")
      .replacingOccurrences(of: "/", with: "_")
    return "ai.refresh.\(configuration.provider.rawValue).\(safeModel)"
  }
}
