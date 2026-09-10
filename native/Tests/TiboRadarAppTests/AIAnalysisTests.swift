import Foundation
import XCTest

@testable import TiboRadarApp

final class AIAnalysisTests: XCTestCase {
  func testAnalysisBuildsProbabilitySnapshot() throws {
    let snapshot = try makeAnalysis().validated().snapshot(
      bundle: bundle(),
      now: ISO8601DateFormatter().date(from: "2026-09-10T12:30:00Z")!
    )

    XCTAssertEqual(snapshot.global24h.label, "8–25%")
    XCTAssertEqual(snapshot.banked24h.label, "4–14%")
    XCTAssertEqual(snapshot.combined24h.label, "10–32%")
    XCTAssertEqual(snapshot.combined24h.likely, 21)
    XCTAssertEqual(snapshot.affectedUserBanked24h?.likely, 80)
    XCTAssertEqual(snapshot.usageAdvice, .watch)
    XCTAssertEqual(snapshot.evidence.first?.label, "Tibo 暗示")
    XCTAssertFalse(snapshot.isStale)
  }

  func testAnalysisRejectsAllZeroOrEmptyRange() {
    let invalid = AIAnalysis(
      global24h: range(0, 0, 0),
      global48h: range(0, 0, 0),
      banked24h: range(0, 0, 0),
      banked48h: range(0, 0, 0),
      combined24h: range(0, 0, 0),
      combined48h: range(0, 0, 0),
      affectedUserBanked24h: nil,
      usageAdvice: .normal,
      analysisNote: "没有新言论，但仍存在历史基础概率。",
      likelyWindow: "暂无可靠时间",
      summary: "短期可能性偏低但不为零。",
      evidence: []
    )

    XCTAssertThrowsError(try invalid.validated())
  }

  func testAnalysisRejects48HourRangeBelow24HourRange() {
    let base = makeAnalysis()
    let invalid = AIAnalysis(
      global24h: base.global24h,
      global48h: range(2, 5, 10),
      banked24h: base.banked24h,
      banked48h: base.banked48h,
      combined24h: base.combined24h,
      combined48h: base.combined48h,
      affectedUserBanked24h: nil,
      usageAdvice: .watch,
      analysisNote: base.analysisNote,
      likelyWindow: base.likelyWindow,
      summary: base.summary,
      evidence: []
    )

    XCTAssertThrowsError(try invalid.validated())
  }

  func testAnalysisRejectsPercentageHiddenInExplanation() {
    let base = makeAnalysis()
    let invalid = AIAnalysis(
      global24h: base.global24h,
      global48h: base.global48h,
      banked24h: base.banked24h,
      banked48h: base.banked48h,
      combined24h: base.combined24h,
      combined48h: base.combined48h,
      affectedUserBanked24h: nil,
      usageAdvice: .watch,
      analysisNote: "我主观认为有 30% 的可能",
      likelyWindow: base.likelyWindow,
      summary: base.summary,
      evidence: []
    )

    XCTAssertThrowsError(try invalid.validated()) { error in
      XCTAssertEqual(
        error as? AIProviderError,
        .invalidAnalysis("AI 返回了未经校准的百分比，已拒绝显示。")
      )
    }
  }

  func testInputContextIncludesHistoricalProbabilityAsAIBaseline() throws {
    let context = try AIInputBuilder.makeContext(bundle: bundle())

    XCTAssertTrue(context.contains("last_reset_at"))
    XCTAssertTrue(context.contains("recent_tibo_feed"))
    XCTAssertTrue(context.contains("rounded_24h"))
  }

  private func makeAnalysis() -> AIAnalysis {
    AIAnalysis(
      global24h: range(8, 15, 25),
      global48h: range(15, 28, 42),
      banked24h: range(4, 8, 14),
      banked48h: range(8, 16, 26),
      combined24h: range(10, 21, 32),
      combined48h: range(19, 38, 55),
      affectedUserBanked24h: range(60, 80, 95),
      usageAdvice: .watch,
      analysisNote: "历史基准偏低，近期只有间接暗示，因此范围保持较宽。",
      likelyWindow: "暂无可靠时间",
      summary: "未来两天仍可能突发重置，但目前没有明确预告。",
      evidence: [
        AIAnalysisEvidence(
          label: "Tibo 暗示",
          detail: "语气指向未来，但没有明确说会重置。",
          category: "positive",
          sourceURL: "https://example.com/post"
        )
      ]
    )
  }

  private func range(_ lower: Int, _ likely: Int, _ upper: Int) -> ForecastProbabilityRange {
    ForecastProbabilityRange(lower: lower, likely: likely, upper: upper)
  }

  private func bundle() -> SourceBundle {
    SourceBundle(
      payloads: [
        .forecast: .object([
          "last_reset_at": .string("2026-09-09T00:00:00Z"),
          "updated_at": .string("2026-09-10T12:00:00Z"),
          "probabilities": .object([
            "rounded_24h": .number(20),
            "range_24h": .object([
              "lower": .number(0.1),
              "upper": .number(0.3),
            ]),
            "range_48h": .object([
              "lower": .number(0.2),
              "upper": .number(0.5),
            ]),
          ]),
          "backtest": .object([
            "status": .string("experimental"),
            "sample_size": .number(307),
            "brier": .number(0.106),
            "better_than_naive": .bool(true),
            "better_than_rate_v2": .bool(false),
          ]),
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
