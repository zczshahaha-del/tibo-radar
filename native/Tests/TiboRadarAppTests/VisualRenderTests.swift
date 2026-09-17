import AppKit
import SwiftUI
import XCTest

@testable import TiboRadarApp

final class VisualRenderTests: XCTestCase {
  @MainActor
  func testPopoverUsesExplicitHeightForEveryPage() throws {
    XCTAssertEqual(
      RadarPopoverView.preferredHeight(showingSettings: false, showingDetails: false),
      350
    )
    XCTAssertEqual(
      RadarPopoverView.preferredHeight(showingSettings: true, showingDetails: false),
      350
    )
    XCTAssertEqual(
      RadarPopoverView.preferredHeight(showingSettings: false, showingDetails: true),
      575
    )

    let model = RadarViewModel(previewSnapshot: previewSnapshot())
    let expandedView = RadarPopoverView(initiallyShowingDetails: true)
      .environmentObject(model)
    let renderer = ImageRenderer(content: expandedView)
    renderer.scale = 1
    let image = try XCTUnwrap(renderer.nsImage)

    XCTAssertEqual(image.size.width, 344, accuracy: 0.5)
    XCTAssertEqual(image.size.height, 575, accuracy: 0.5)
  }

  @MainActor
  func testRenderPopoverWhenRequested() throws {
    guard
      let outputPath = ProcessInfo.processInfo.environment[
        "TIBO_RADAR_RENDER_PATH"
      ]
    else {
      throw XCTSkip("Set TIBO_RADAR_RENDER_PATH to render the popover")
    }

    let snapshot = PredictionSnapshot(
      generatedAt: Date(),
      global24h: ForecastProbabilityRange(lower: 8, likely: 15, upper: 25),
      global48h: ForecastProbabilityRange(lower: 15, likely: 28, upper: 42),
      banked24h: ForecastProbabilityRange(lower: 4, likely: 8, upper: 14),
      banked48h: ForecastProbabilityRange(lower: 8, likely: 16, upper: 26),
      combined24h: ForecastProbabilityRange(lower: 10, likely: 21, upper: 32),
      combined48h: ForecastProbabilityRange(lower: 19, likely: 38, upper: 55),
      affectedUserBanked24h: ForecastProbabilityRange(lower: 60, likely: 80, upper: 95),
      usageAdvice: .watch,
      analysisNote: "AI 综合历史频率、近期言论和服务状态后，认为事件仍有可能发生，但没有明显升温。",
      summary: "有基础概率，可以关注，但还没到需要立刻改变用量安排的程度。",
      conditionalWindow: "9月11日 07:00–10:00",
      historicalBaseline: ProbabilityEstimate(
        lower24h: 12,
        upper24h: 37,
        lower48h: 25,
        upper48h: 55,
        sampleSize: 307,
        brierScore: 0.106,
        quality: .historicalEstimate
      ),
      baselineNote: "历史基准（307 次回放）：24 小时 12–37%，48 小时 25–55%。",
      lastResetAt: Date().addingTimeInterval(-2.2 * 86_400),
      dataUpdatedAt: Date(),
      isStale: false,
      evidence: [
        Evidence(
          id: "tibo-post",
          label: "Tibo 近期言论",
          detail: "AI 判断语气指向未来，但没有明确说会重置。",
          category: "positive"
        ),
        Evidence(
          id: "counter",
          label: "缺少明确时间",
          detail: "没有找到官方日期或面向所有用户的承诺。",
          category: "negative"
        ),
        Evidence(
          id: "targeted",
          label: "定向补发",
          detail: "仅故障时段内受影响的用户，不提高普发概率。",
          category: "targeted"
        ),
      ],
      latestEvents: [],
      sourceErrors: []
    )
    let model = RadarViewModel(previewSnapshot: snapshot)
    let view = RadarPopoverView()
      .environmentObject(model)
      .environment(\.colorScheme, .dark)
    try render(view, size: CGSize(width: 344, height: 350), to: outputPath)
  }

  @MainActor
  func testRenderExpandedEvidenceWhenRequested() throws {
    guard
      let outputPath = ProcessInfo.processInfo.environment[
        "TIBO_RADAR_EXPANDED_RENDER_PATH"
      ]
    else {
      throw XCTSkip("Set TIBO_RADAR_EXPANDED_RENDER_PATH to render expanded evidence")
    }

    let model = RadarViewModel(previewSnapshot: previewSnapshot())
    let view = RadarPopoverView(initiallyShowingDetails: true)
      .environmentObject(model)
      .environment(\.colorScheme, .dark)
    try render(view, size: CGSize(width: 344, height: 575), to: outputPath)
  }

  @MainActor
  func testRenderAISettingsWhenRequested() throws {
    guard
      let outputPath = ProcessInfo.processInfo.environment[
        "TIBO_RADAR_SETTINGS_RENDER_PATH"
      ]
    else {
      throw XCTSkip("Set TIBO_RADAR_SETTINGS_RENDER_PATH to render AI settings")
    }

    let model = RadarViewModel(previewSnapshot: previewSnapshot())
    let view = RadarPopoverView(initiallyShowingSettings: true)
      .environmentObject(model)
      .environment(\.colorScheme, .dark)
    try render(view, size: CGSize(width: 344, height: 350), to: outputPath)
  }

  @MainActor
  private func render<V: View>(
    _ view: V,
    size: CGSize,
    to outputPath: String
  ) throws {
    let renderer = ImageRenderer(content: view)
    renderer.proposedSize = ProposedViewSize(size)
    renderer.scale = 2
    guard let image = renderer.nsImage,
      let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:])
    else {
      XCTFail("Could not render view")
      return
    }
    try png.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
    XCTAssertGreaterThan(png.count, 10_000)
  }

  private func previewSnapshot() -> PredictionSnapshot {
    let now = Date()
    return PredictionSnapshot(
      generatedAt: now,
      global24h: ForecastProbabilityRange(lower: 8, likely: 15, upper: 25),
      global48h: ForecastProbabilityRange(lower: 15, likely: 28, upper: 42),
      banked24h: ForecastProbabilityRange(lower: 4, likely: 8, upper: 14),
      banked48h: ForecastProbabilityRange(lower: 8, likely: 16, upper: 26),
      combined24h: ForecastProbabilityRange(lower: 10, likely: 21, upper: 32),
      combined48h: ForecastProbabilityRange(lower: 19, likely: 38, upper: 55),
      affectedUserBanked24h: nil,
      usageAdvice: .watch,
      analysisNote: "AI evidence",
      summary: "No actionable signal",
      conditionalWindow: "暂无集中时段",
      historicalBaseline: ProbabilityEstimate(
        lower24h: 12,
        upper24h: 37,
        lower48h: 25,
        upper48h: 55,
        sampleSize: 307,
        brierScore: 0.106,
        quality: .historicalEstimate
      ),
      baselineNote: "历史基准（307 次回放）：24 小时 12–37%，48 小时 25–55%。",
      lastResetAt: nil,
      dataUpdatedAt: now,
      isStale: false,
      evidence: [
        Evidence(
          id: "preview-signal",
          label: "上一轮重置刚完成",
          detail: "Tibo 约 7 小时前确认重置已经传播完毕，短时间内再次重置的可能性下降。",
          category: "negative",
          sourceURL: URL(string: "https://x.com/tibo_maker"),
          sourceDate: now.addingTimeInterval(-7 * 60 * 60)
        ),
        Evidence(
          id: "preview-counter",
          label: "没有新的未来预告",
          detail: "近期 Tibo 原文没有再次承诺重置额度，也没有面向所有用户的重置卡消息。",
          category: "negative",
          sourceURL: URL(string: "https://x.com/tibo_maker"),
          sourceDate: now.addingTimeInterval(-2 * 24 * 60 * 60)
        ),
        Evidence(
          id: "preview-history",
          label: "48 小时仍保留历史机会",
          detail: "预测窗口变长后，历史上自然发生重置或发卡的累计概率会升高。",
          category: "context",
          sourceDate: now.addingTimeInterval(-6 * 24 * 60 * 60)
        ),
      ],
      latestEvents: [],
      sourceErrors: []
    )
  }
}
