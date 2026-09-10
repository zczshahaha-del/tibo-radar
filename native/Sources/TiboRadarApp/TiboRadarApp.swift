import SwiftUI

@main
struct TiboRadarApp: App {
    @StateObject private var model = RadarViewModel()

    var body: some Scene {
        MenuBarExtra {
            RadarPopoverView()
                .environmentObject(model)
        } label: {
            Image(systemName: "dot.radiowaves.up.forward")
                .accessibilityLabel("Tibo Radar")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class RadarViewModel: ObservableObject {
    @Published var statusText = "正在接入公开信号…"
}

struct RadarPopoverView: View {
    @EnvironmentObject private var model: RadarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Tibo Radar")
                        .font(.title2.weight(.bold))
                    Label("运行中", systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                Spacer()
                Button {
                    model.statusText = "正在接入公开信号…"
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("刷新")
            }

            VStack(spacing: 8) {
                Text("—")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)
                Text("未来 24 小时综合概率")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))

            Label(model.statusText, systemImage: "antenna.radiowaves.left.and.right")
                .foregroundStyle(.secondary)

            Divider()

            HStack {
                Label("每 15 分钟检查", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("退出") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(.ultraThinMaterial)
    }
}
