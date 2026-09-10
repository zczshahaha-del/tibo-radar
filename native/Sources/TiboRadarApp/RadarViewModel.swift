import Foundation
import SwiftUI

@MainActor
final class RadarViewModel: ObservableObject {
    @Published private(set) var snapshot: PredictionSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?

    private let client: RadarClient
    private let predictor: Predictor
    private let notifications: NotificationManager
    private var refreshTimer: Timer?

    init(
        client: RadarClient = RadarClient(),
        predictor: Predictor = Predictor(),
        notifications: NotificationManager = NotificationManager()
    ) {
        self.client = client
        self.predictor = predictor
        self.notifications = notifications

        Task { [weak self] in
            await self?.refresh()
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) {
            [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let bundle = await client.fetchAll()
        let next = predictor.predict(bundle: bundle)
        snapshot = next
        lastError = bundle.payloads.isEmpty
            ? "没有可用的网络数据或缓存，请稍后重试。"
            : nil
        await notifications.process(next)
    }
}
