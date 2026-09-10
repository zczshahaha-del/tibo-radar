import Foundation
import UserNotifications

struct NotificationDecision: Equatable, Sendable {
  let title: String
  let body: String
}

enum NotificationPolicy {
  static func decide(
    previousSignal: SignalStrength?,
    previousEventIDs: Set<String>,
    snapshot: PredictionSnapshot
  ) -> NotificationDecision? {
    guard let previousSignal else { return nil }

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

    if previousSignal.rank < SignalStrength.strong.rank,
      snapshot.overallSignal.rank >= SignalStrength.strong.rank
    {
      let reason = snapshot.evidence.first?.detail ?? snapshot.analysisNote
      return NotificationDecision(
        title: snapshot.overallSignal == .announced
          ? "Tibo Radar：发现明确预告"
          : "Tibo Radar：发现值得关注的信号",
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

  func process(_ snapshot: PredictionSnapshot) async {
    let previousSignal = defaults.string(forKey: "previousSignalStrength")
      .flatMap(SignalStrength.init(rawValue:))
    let previousEventIDs = Set(
      defaults.stringArray(forKey: "previousEventIDs") ?? []
    )
    let decision = NotificationPolicy.decide(
      previousSignal: previousSignal,
      previousEventIDs: previousEventIDs,
      snapshot: snapshot
    )

    defaults.set(snapshot.overallSignal.rawValue, forKey: "previousSignalStrength")
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
