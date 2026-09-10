import AppKit
import SwiftUI
import XCTest
@testable import TiboRadarApp

final class VisualRenderTests: XCTestCase {
    @MainActor
    func testRenderPopoverWhenRequested() throws {
        guard let outputPath = ProcessInfo.processInfo.environment[
            "TIBO_RADAR_RENDER_PATH"
        ] else {
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
            confidence: "low",
            confidenceNote: "历史样本较少",
            level: .green,
            likelyWindow: "北京时间 07:00–10:00",
            lastResetAt: Date().addingTimeInterval(-2.2 * 86_400),
            dataUpdatedAt: Date(),
            isStale: false,
            evidence: [
                Evidence(
                    id: "cadence",
                    label: "历史节奏",
                    detail: "距上次重置 2.2 天；近期典型间隔 2.1 天。",
                    category: "baseline"
                ),
                Evidence(
                    id: "targeted",
                    label: "定向补发",
                    detail: "仅故障时段内受影响的用户，不提高普发概率。",
                    category: "targeted"
                ),
                Evidence(
                    id: "incident",
                    label: "Codex 状态事件",
                    detail: "Investigating unexpected usage limit resets",
                    category: "context",
                    delta: 5
                ),
            ],
            latestEvents: [],
            sourceErrors: []
        )
        let model = RadarViewModel(previewSnapshot: snapshot)
        let view = RadarPopoverView()
            .environmentObject(model)
            .preferredColorScheme(.dark)
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: 390, height: 610)
        renderer.scale = 2

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            XCTFail("Could not render popover")
            return
        }
        try png.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        XCTAssertGreaterThan(png.count, 10_000)
    }
}
