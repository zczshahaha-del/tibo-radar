import Foundation
import XCTest

@testable import TiboRadarApp

final class AIAnalysisTests: XCTestCase {
  func testAnalysisBuildsSemanticSnapshotWithoutModelProbability() throws {
    let analysis = AIAnalysis(
      globalSignal: .weak,
      bankedSignal: .none,
      affectedUserSignal: .announced,
      analysisNote: "有一条暗示，但没有明确的未来承诺。",
      likelyWindow: "暂无可靠时间",
      summary: "可以继续观察，暂时不用改变用量安排。",
      evidence: [
        AIAnalysisEvidence(
          label: "Tibo 暗示",
          detail: "语气指向未来，但没有明确说会重置。",
          category: "positive",
          sourceURL: "https://example.com/post"
        )
      ]
    )
    let now = ISO8601DateFormatter().date(from: "2026-09-10T12:30:00Z")!
    let snapshot = try analysis.validated().snapshot(bundle: bundle(), now: now)

    XCTAssertEqual(snapshot.globalSignal, .weak)
    XCTAssertEqual(snapshot.bankedSignal, .none)
    XCTAssertEqual(snapshot.overallSignal, .weak)
    XCTAssertEqual(snapshot.affectedUserSignal, .announced)
    XCTAssertEqual(snapshot.evidence.first?.label, "Tibo 暗示")
    XCTAssertNil(snapshot.calibratedProbability)
    XCTAssertEqual(snapshot.probabilityNote, "还没有足够的历史预测记录，所以先不显示数字。")
    XCTAssertFalse(snapshot.isStale)
  }

  func testAnalysisRejectsMissingExplanation() {
    let analysis = AIAnalysis(
      globalSignal: .none,
      bankedSignal: .none,
      affectedUserSignal: nil,
      analysisNote: "",
      likelyWindow: "暂无可靠时间",
      summary: "暂无新信号",
      evidence: []
    )

    XCTAssertThrowsError(try analysis.validated())
  }

  func testAnalysisRejectsPercentageHiddenInExplanation() {
    let analysis = AIAnalysis(
      globalSignal: .weak,
      bankedSignal: .none,
      affectedUserSignal: nil,
      analysisNote: "我主观认为有 30% 的可能",
      likelyWindow: "暂无可靠时间",
      summary: "有一点迹象",
      evidence: []
    )

    XCTAssertThrowsError(try analysis.validated()) { error in
      XCTAssertEqual(
        error as? AIProviderError,
        .invalidAnalysis("AI 返回了未经校准的百分比，已拒绝显示。")
      )
    }
  }

  func testInputContextExcludesLegacyForecastProbability() throws {
    let context = try AIInputBuilder.makeContext(bundle: bundle())

    XCTAssertTrue(context.contains("last_reset_at"))
    XCTAssertTrue(context.contains("recent_tibo_feed"))
    XCTAssertFalse(context.contains("rounded_24h"))
  }

  private func bundle() -> SourceBundle {
    SourceBundle(
      payloads: [
        .forecast: .object([
          "last_reset_at": .string("2026-09-09T00:00:00Z"),
          "updated_at": .string("2026-09-10T12:00:00Z"),
          "probabilities": .object(["rounded_24h": .number(99)]),
        ]),
        .timeline: .object([
          "updated_at": .string("2026-09-10T12:00:00Z"),
          "events": .array([]),
        ]),
        .feed: .object([
          "updated_at": .string("2026-09-10T12:00:00Z"),
          "events": .array([
            .object([
              "id": .string("signal-1"),
              "group": .string("signal"),
              "text": .string("A new public signal"),
              "observed_at": .string("2026-09-10T11:00:00Z"),
            ])
          ]),
        ]),
      ],
      cacheFallbacks: [],
      errors: []
    )
  }
}
