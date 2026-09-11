import AppKit
import SwiftUI

struct RadarPopoverView: View {
  @EnvironmentObject private var model: RadarViewModel
  @State private var showingSettings = false

  var body: some View {
    VStack(spacing: 0) {
      header
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)

      if showingSettings {
        AISettingsView {
          showingSettings = false
        }
        .environmentObject(model)
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
      } else if let snapshot = model.snapshot {
        VStack(spacing: 12) {
          hero(snapshot)
          categories(snapshot)
          evidence(snapshot)
          if !snapshot.sourceErrors.isEmpty {
            sourceWarning(snapshot)
          }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
      } else {
        loading
      }

      footer
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
        .background(.black.opacity(0.12))
    }
    .frame(width: 390, height: 660)
    .background(.ultraThinMaterial)
  }

  private var header: some View {
    HStack(spacing: 12) {
      ZStack {
        Circle().fill(Color.green.opacity(0.14))
        Image(systemName: "dot.radiowaves.up.forward")
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(.green)
      }
      .frame(width: 34, height: 34)

      VStack(alignment: .leading, spacing: 2) {
        Text("Tibo Radar")
          .font(.system(size: 17, weight: .bold))
        HStack(spacing: 5) {
          Circle()
            .fill(model.hasAPIKey ? Color.green : Color.orange)
            .frame(width: 6, height: 6)
          Text(statusText)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Spacer()

      HStack(spacing: 13) {
        Button {
          showingSettings.toggle()
        } label: {
          Image(systemName: showingSettings ? "chevron.left" : "gearshape.fill")
            .font(.system(size: 13, weight: .semibold))
        }
        .buttonStyle(.plain)
        .help(showingSettings ? "返回预测" : "AI 设置")
        .accessibilityLabel(showingSettings ? "返回预测" : "AI 设置")

        Button {
          Task { await model.refresh() }
        } label: {
          Image(systemName: "arrow.clockwise")
            .font(.system(size: 14, weight: .semibold))
            .rotationEffect(model.isRefreshing ? .degrees(180) : .zero)
        }
        .buttonStyle(.plain)
        .disabled(model.isRefreshing || !model.hasAPIKey || showingSettings)
        .help("让 AI 重新搜索并判断")
        .accessibilityLabel("让 AI 重新搜索并判断")
      }
    }
  }

  private func hero(_ snapshot: PredictionSnapshot) -> some View {
    VStack(spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 6) {
          Label("AI 综合预测", systemImage: "circle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(levelColor(snapshot.combined24h.likely))
          Text("\(snapshot.combined24h.likely)%")
            .font(.system(size: 46, weight: .bold, design: .rounded))
            .minimumScaleFactor(0.75)
            .lineLimit(1)
          Text("未来 24 小时 · 两种福利至少一种")
            .font(.callout)
            .foregroundStyle(.secondary)
          Text("可能范围 \(snapshot.combined24h.label)")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        Spacer()
        VStack(alignment: .leading, spacing: 12) {
          metric(
            "48 小时",
            "\(snapshot.combined48h.likely)%",
            detail: "可能范围 \(snapshot.combined48h.label)"
          )
          metric("现在怎么做", snapshot.usageAdvice.label)
          metric(
            "若发生，较可能在",
            PredictionCopy.conditionalWindow(snapshot.conditionalWindow),
            lineLimit: 2
          )
        }
        .frame(width: 128, alignment: .leading)
      }
    }
    .padding(18)
    .background(
      LinearGradient(
        colors: [levelColor(snapshot.combined24h.likely).opacity(0.16), .black.opacity(0.03)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      ),
      in: RoundedRectangle(cornerRadius: 17)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 17)
        .stroke(levelColor(snapshot.combined24h.likely).opacity(0.32), lineWidth: 1)
    }
  }

  private func metric(
    _ label: String,
    _ value: String,
    lineLimit: Int = 1,
    detail: String? = nil
  ) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label.uppercased())
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(.tertiary)
      Text(value)
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .lineLimit(lineLimit)
        .minimumScaleFactor(0.75)
      if let detail {
        Text(detail)
          .font(.system(size: 9, weight: .medium))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.72)
      }
    }
  }

  private func categories(_ snapshot: PredictionSnapshot) -> some View {
    VStack(spacing: 0) {
      categoryRow(
        icon: "globe.asia.australia.fill",
        title: "全局重置",
        range: snapshot.global24h,
        color: .green
      )
      Divider().padding(.leading, 46)
      categoryRow(
        icon: "creditcard.fill",
        title: "普发重置卡",
        range: snapshot.banked24h,
        color: .mint
      )
      if let affected = snapshot.affectedUserBanked24h {
        Divider().padding(.leading, 46)
        categoryRow(
          icon: "exclamationmark.triangle.fill",
          title: "故障补发",
          range: affected,
          color: .orange,
          badge: "仅受影响用户"
        )
      }
    }
    .padding(.horizontal, 14)
    .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 15))
    .overlay {
      RoundedRectangle(cornerRadius: 15)
        .stroke(.white.opacity(0.06), lineWidth: 1)
    }
  }

  private func categoryRow(
    icon: String,
    title: String,
    range: ForecastProbabilityRange,
    color: Color,
    badge: String? = nil
  ) -> some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(color)
        .frame(width: 20)
      VStack(alignment: .leading, spacing: 3) {
        Text(title).font(.system(size: 13, weight: .semibold))
        if let badge {
          Text(badge)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.orange.opacity(0.12), in: Capsule())
        }
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 1) {
        Text("\(range.likely)%")
          .font(.system(size: 14, weight: .bold))
        Text("范围 \(range.label)")
          .font(.system(size: 9, weight: .medium))
          .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 11)
  }

  private func evidence(_ snapshot: PredictionSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("AI 为什么这么预测")
          .font(.system(size: 12, weight: .bold))
        Spacer()
        if snapshot.isStale {
          Label("缓存", systemImage: "clock.arrow.circlepath")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.orange)
        }
      }

      Text(snapshot.analysisNote)
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .lineLimit(3)
        .fixedSize(horizontal: false, vertical: true)

      Divider()

      VStack(alignment: .leading, spacing: 3) {
        Text("AI 参考了什么")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(.tertiary)
        Text(snapshot.baselineNote)
          .font(.system(size: 10))
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }

      Divider()

      Text("主要依据")
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.tertiary)

      ForEach(snapshot.evidence.prefix(2)) { item in
        HStack(alignment: .top, spacing: 9) {
          Circle()
            .fill(evidenceColor(item.category))
            .frame(width: 6, height: 6)
            .padding(.top, 5)
          VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
              Text(item.label)
                .font(.system(size: 11, weight: .semibold))
              if item.delta != 0 {
                Text(item.delta > 0 ? "+\(item.delta)" : "\(item.delta)")
                  .font(.system(size: 9, weight: .bold))
                  .foregroundStyle(item.delta > 0 ? .green : .red)
              }
            }
            Text(item.detail)
              .font(.system(size: 10))
              .foregroundStyle(.secondary)
              .lineLimit(2)
          }
          Spacer(minLength: 0)
          if let sourceURL = item.sourceURL {
            Link(destination: sourceURL) {
              Image(systemName: "arrow.up.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
    .padding(14)
    .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 15))
  }

  private func sourceWarning(_ snapshot: PredictionSnapshot) -> some View {
    Label(
      snapshot.isStale ? "部分来源异常，当前使用最近缓存" : "部分公开来源暂时不可用",
      systemImage: "wifi.exclamationmark"
    )
    .font(.caption)
    .foregroundStyle(.orange)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(10)
    .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
  }

  private var loading: some View {
    VStack(spacing: 14) {
      if model.isRefreshing {
        ProgressView().controlSize(.small)
      } else {
        Image(systemName: "key.horizontal.fill")
          .font(.system(size: 26))
          .foregroundStyle(.orange)
      }
      Text(model.lastError ?? "正在读取 Tibo 与 Codex 的公开信号…")
        .font(.callout)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
      if !model.hasAPIKey {
        Button("打开 AI 设置") {
          showingSettings = true
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(30)
  }

  private var footer: some View {
    HStack {
      Label(
        "\(model.selectedProvider.displayName) · \(AIRefreshSchedule.label)",
        systemImage: "brain.head.profile"
      )
        .font(.caption)
        .foregroundStyle(.secondary)
      Spacer()
      if let date = model.snapshot?.dataUpdatedAt {
        Text(date, style: .relative)
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }
      Button {
        NSApplication.shared.terminate(nil)
      } label: {
        Image(systemName: "xmark.circle.fill")
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.borderless)
      .font(.caption)
      .help("退出 Tibo Radar")
      .accessibilityLabel("退出 Tibo Radar")
    }
  }

  private var statusText: String {
    if model.isRefreshing { return "AI 正在判断" }
    if !model.hasAPIKey { return "需要 API Key" }
    return "AI 概率预测已启用"
  }

  private func levelColor(_ probability: Int) -> Color {
    if probability >= 70 { return .red }
    if probability >= 50 { return .orange }
    if probability >= 30 { return .yellow }
    return .green
  }

  private func evidenceColor(_ category: String) -> Color {
    switch category {
    case "positive": .green
    case "negative": .red
    case "targeted": .orange
    default: .secondary
    }
  }

}
