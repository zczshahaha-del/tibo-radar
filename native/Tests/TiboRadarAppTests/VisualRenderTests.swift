import AppKit
import SwiftUI
import XCTest

@testable import TiboRadarApp

final class VisualRenderTests: XCTestCase {
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
      .preferredColorScheme(.dark)
    try render(view, size: CGSize(width: 390, height: 660), to: outputPath)
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
    let view = VStack(spacing: 0) {
      Text("Tibo Radar")
        .font(.headline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
      AISettingsView(onDone: {})
        .environmentObject(model)
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
      Spacer(minLength: 0)
    }
    .frame(width: 390, height: 660)
    .background(.ultraThinMaterial)
    .preferredColorScheme(.dark)
    try render(view, size: CGSize(width: 390, height: 660), to: outputPath)
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
    PredictionSnapshot(
      generatedAt: Date(),
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
      dataUpdatedAt: Date(),
      isStale: false,
      evidence: [],
      latestEvents: [],
      sourceErrors: []
    )
  }
}
