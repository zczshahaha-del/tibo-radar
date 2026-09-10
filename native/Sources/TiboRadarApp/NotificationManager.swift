import Foundation
import UserNotifications

struct NotificationDecision: Equatable, Sendable {
  let title: String
  let body: String
}

enum NotificationPolicy {
  static func decide(
    previousProbability: Int?,
    previousEventIDs: Set<String>,
    snapshot: PredictionSnapshot,
    threshold: Int = 65
  ) -> NotificationDecision? {
    guard let previousProbability else { return nil }

    let newEvent = snapshot.latestEvents.first { event in
      !previousEventIDs.contains(event.id)
        && ["reset", "credits", "banked"].contains(event.kind)
    }
    if let newEvent {
      return NotificationDecision(
        title: "Tibo Radar：发现新的重置信号",
        body: String(newEvent.title.prefix(180))
      )
    }

    if previousProbability < threshold, snapshot.combined24h >= threshold {
      let reason = snapshot.evidence.last?.detail ?? snapshot.level.label
      return NotificationDecision(
        title: "Tibo Radar：24 小时概率升至 \(snapshot.combined24h)%",
        body: "\(reason) 最可能时段：\(snapshot.likelyWindow)"
      )
    }
    return nil
  }
}

actor NotificationManager {
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func prepareAuthorization() async {
    _ = try? await UNUserNotificationCenter.current().requestAuthorization(
      options: [.alert, .sound]
    )
  }

  func process(_ snapshot: PredictionSnapshot, threshold: Int = 65) async {
    let previousProbability: Int? =
      defaults.object(
        forKey: "previousCombined24h"
      ) as? Int
    let previousEventIDs = Set(
      defaults.stringArray(forKey: "previousEventIDs") ?? []
    )
    let decision = NotificationPolicy.decide(
      previousProbability: previousProbability,
      previousEventIDs: previousEventIDs,
      snapshot: snapshot,
      threshold: threshold
    )

    defaults.set(snapshot.combined24h, forKey: "previousCombined24h")
    defaults.set(snapshot.latestEvents.map(\.id), forKey: "previousEventIDs")

    guard let decision else { return }
    let center = UNUserNotificationCenter.current()
    do {
      let granted = try await center.requestAuthorization(options: [.alert, .sound])
      guard granted else { return }
      let content = UNMutableNotificationContent()
      content.title = decision.title
      content.body = decision.body
      content.sound = .default
      let request = UNNotificationRequest(
        identifier: UUID().uuidString,
        content: content,
        trigger: nil
      )
      try await center.add(request)
    } catch {
      // Notification permission or delivery errors should never stop predictions.
    }
  }
}
