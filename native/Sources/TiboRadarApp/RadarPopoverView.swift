import SwiftUI

struct RadarPopoverView: View {
  @EnvironmentObject private var model: RadarViewModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var showingSettings = false
  @State private var showingDetails = false

  init(
    initiallyShowingDetails: Bool = false,
    initiallyShowingSettings: Bool = false
  ) {
    _showingDetails = State(initialValue: initiallyShowingDetails)
    _showingSettings = State(initialValue: initiallyShowingSettings)
  }

  var body: some View {
    VStack(spacing: 0) {
      header

      if showingSettings {
        AISettingsView()
        .environmentObject(model)
      } else if let snapshot = model.snapshot {
        forecast(snapshot)
        if !showingDetails {
          Spacer(minLength: 0)
        }
        footer
        if showingDetails {
          detailedEvidence(snapshot)
            .transition(.opacity)
        }
      } else {
        loading
      }
    }
    .frame(width: 344)
    .frame(height: compactPanelHeight, alignment: .top)
    .background(.ultraThinMaterial)
  }

  private var header: some View {
    HStack(spacing: 10) {
      ZStack {
        Circle().fill(Color.green.opacity(0.13))
        Image(systemName: "dot.radiowaves.up.forward")
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(.green)
      }
      .frame(width: 32, height: 32)

      VStack(alignment: .leading, spacing: 1) {
        Text("Tibo Radar")
          .font(.system(size: 16, weight: .semibold))
        Text(headerSubtitle)
          .font(.system(size: 11))
          .foregroundStyle(headerSubtitleColor)
          .lineLimit(1)
      }

      Spacer()

      HStack(spacing: 2) {
        Button {
          showingSettings.toggle()
        } label: {
          Image(systemName: showingSettings ? "chevron.left" : "gearshape")
            .font(.system(size: 13, weight: .medium))
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(showingSettings ? "返回预测" : "AI 设置")
        .accessibilityLabel(showingSettings ? "返回预测" : "AI 设置")

        if !showingSettings {
          Button {
            Task { await model.refresh() }
          } label: {
            Image(systemName: "arrow.clockwise")
              .font(.system(size: 13, weight: .medium))
              .rotationEffect(model.isRefreshing ? .degrees(180) : .zero)
              .frame(width: 30, height: 30)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .disabled(model.isRefreshing || !model.hasAPIKey)
          .help("让 AI 重新搜索并判断")
          .accessibilityLabel("让 AI 重新搜索并判断")
        }
      }
    }
    .padding(.horizontal, 16)
    .padding(.top, 14)
    .padding(.bottom, 10)
    .fixedSize(horizontal: false, vertical: true)
    .layoutPriority(1)
  }

  private func forecast(_ snapshot: PredictionSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("重置额度或重置卡")
        .font(.system(size: 15, weight: .semibold))
        .padding(.bottom, 12)

      HStack(spacing: 0) {
        horizon("24 小时", probability: snapshot.combined24h.likely)

        Divider()
          .frame(height: 52)

        horizon("48 小时", probability: snapshot.combined48h.likely)
      }
      .padding(.vertical, 12)
      .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))

      Divider()
        .padding(.top, 16)
        .padding(.bottom, 10)

      Text("24 小时内")
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.bottom, 3)

      probabilityRow("重置额度", probability: snapshot.global24h.likely)
      probabilityRow("重置卡", probability: snapshot.banked24h.likely)
    }
    .padding(.horizontal, 18)
    .padding(.top, 12)
    .padding(.bottom, 16)
  }

  private func horizon(_ title: String, probability: Int) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
      Text("\(probability)%")
        .font(.system(size: 28, weight: .semibold, design: .rounded))
        .monospacedDigit()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 16)
  }

  private func probabilityRow(_ title: String, probability: Int) -> some View {
    HStack(spacing: 16) {
      Text(title)
        .font(.system(size: 13))
      Spacer()
      Text("\(probability)%")
        .font(.system(size: 14, weight: .semibold, design: .rounded))
        .monospacedDigit()
    }
    .frame(height: 38)
  }

  private var footer: some View {
    HStack(spacing: 8) {
      Text("\(model.selectedProvider.displayName) · \(AIRefreshSchedule.label)")
        .font(.system(size: 10))
        .foregroundStyle(.secondary)

      Spacer()

      Button {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
          showingDetails.toggle()
        }
      } label: {
        HStack(spacing: 5) {
          Text(showingDetails ? "收起依据" : "详细依据")
            .contentTransition(.opacity)
          Image(systemName: "chevron.down")
            .font(.system(size: 8, weight: .semibold))
            .rotationEffect(showingDetails ? .degrees(180) : .zero)
        }
        .font(.system(size: 10, weight: .medium))
        .frame(height: 30)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(showingDetails ? "收起详细依据" : "查看详细依据")
    }
    .padding(.horizontal, 16)
    .frame(height: 44)
    .background(Color.primary.opacity(0.035))
    .overlay(alignment: .top) { Divider() }
  }

  private func detailedEvidence(_ snapshot: PredictionSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      Text("主要依据")
        .font(.system(size: 13, weight: .semibold))
        .padding(.bottom, 1)

      if snapshot.evidence.isEmpty {
        Text(snapshot.analysisNote)
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      } else {
        ForEach(snapshot.evidence.prefix(3)) { item in
          evidenceRow(item)
        }
      }
    }
    .padding(.horizontal, 18)
    .padding(.top, 12)
    .padding(.bottom, 16)
    .overlay(alignment: .top) { Divider() }
  }

  private func evidenceRow(_ item: Evidence) -> some View {
    HStack(alignment: .top, spacing: 9) {
      Circle()
        .fill(evidenceColor(item.category))
        .frame(width: 7, height: 7)
        .padding(.top, 5)

      VStack(alignment: .leading, spacing: 3) {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text(item.label)
            .font(.system(size: 11, weight: .semibold))

          if let sourceDate = item.sourceDate {
            Text(evidenceDateLabel(sourceDate))
              .font(.system(size: 9, weight: .medium))
              .foregroundStyle(.tertiary)
          }
        }
        Text(item.detail)
          .font(.system(size: 10))
          .foregroundStyle(.secondary)
          .lineLimit(3)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 0)

      if let sourceURL = item.sourceURL {
        Link(destination: sourceURL) {
          Image(systemName: "arrow.up.right.square")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("查看原始来源")
        .accessibilityLabel("查看 \(item.label) 的原始来源")
      }
    }
    .padding(.vertical, 6)
  }

  private func evidenceDateLabel(_ date: Date) -> String {
    let dateText = date.formatted(
      Date.FormatStyle()
        .month(.defaultDigits)
        .day(.defaultDigits)
        .locale(Locale(identifier: "zh_CN"))
    )
    guard Date().timeIntervalSince(date) > 72 * 60 * 60 else { return dateText }
    return "历史 · \(dateText)"
  }

  private var loading: some View {
    VStack(spacing: 14) {
      if model.isRefreshing {
        ProgressView().controlSize(.small)
      } else {
        Image(systemName: "key.horizontal.fill")
          .font(.system(size: 24))
          .foregroundStyle(.orange)
      }
      Text(model.lastError ?? "正在读取 Tibo 与 Codex 的公开信号…")
        .font(.system(size: 12))
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
    .frame(maxWidth: .infinity)
    .frame(height: 230)
    .padding(.horizontal, 28)
  }

  private var headerSubtitle: String {
    if model.isRefreshing { return "正在更新…" }
    if !model.hasAPIKey { return "需要 API Key" }
    guard let snapshot = model.snapshot else { return "等待第一次预测" }
    return PredictionCopy.lastRefresh(snapshot.generatedAt)
  }

  private var headerSubtitleColor: Color {
    if !model.hasAPIKey || model.snapshot?.isStale == true { return .orange }
    return .secondary
  }

  private var compactPanelHeight: CGFloat? {
    showingSettings || !showingDetails ? 350 : nil
  }

  private func evidenceColor(_ category: String) -> Color {
    switch category {
    case "positive": .green
    case "negative": .red
    case "targeted": .orange
    default: .orange
    }
  }
}
