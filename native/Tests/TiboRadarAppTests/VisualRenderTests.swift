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
      global24h: 32,
      global48h: 50,
      banked24h: 8,
      banked48h: 15,
      combined24h: 37,
      combined48h: 57,
      affectedUserBanked24h: 94,
      confidence: "medium",
      confidenceNote: "AI 找到一条暗示，但没有明确预告。",
      level: .green,
      likelyWindow: "北京时间 07:00–10:00",
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
    try render(view, size: CGSize(width: 390, height: 610), to: outputPath)
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
    .frame(width: 390, height: 610)
    .background(.ultraThinMaterial)
    .preferredColorScheme(.dark)
    try render(view, size: CGSize(width: 390, height: 610), to: outputPath)
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
      global24h: 32,
      global48h: 50,
      banked24h: 8,
      banked48h: 15,
      combined24h: 37,
      combined48h: 57,
      affectedUserBanked24h: nil,
      confidence: "medium",
      confidenceNote: "AI evidence",
      level: .green,
      likelyWindow: "无法可靠判断",
      lastResetAt: nil,
      dataUpdatedAt: Date(),
      isStale: false,
      evidence: [],
      latestEvents: [],
      sourceErrors: []
    )
  }
}
