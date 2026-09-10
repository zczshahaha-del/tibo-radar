import Foundation
import XCTest

@testable import TiboRadarApp

final class AIAnalysisTests: XCTestCase {
  func testAnalysisBuildsSnapshotWithoutRuleScoring() throws {
    let analysis = AIAnalysis(
      global24h: 30,
      global48h: 55,
      banked24h: 20,
      banked48h: 40,
      affectedUserBanked24h: 91,
      confidence: "medium",
      confidenceNote: "有一条官方信号，但没有明确日期。",
      likelyWindow: "北京时间明晚",
      summary: "需要关注，但仍缺少明确预告。",
      evidence: [
        AIAnalysisEvidence(
          label: "Tibo 暗示",
          detail: "语气指向未来，但没有明确说重置。",
          category: "positive",
          sourceURL: "https://example.com/post"
        )
      ]
    )
    let now = ISO8601DateFormatter().date(from: "2026-09-10T12:30:00Z")!
    let snapshot = try analysis.validated().snapshot(bundle: bundle(), now: now)

    XCTAssertEqual(snapshot.global24h, 30)
    XCTAssertEqual(snapshot.banked24h, 20)
    XCTAssertEqual(snapshot.combined24h, 44)
    XCTAssertEqual(snapshot.affectedUserBanked24h, 91)
    XCTAssertEqual(snapshot.confidence, "medium")
    XCTAssertEqual(snapshot.evidence.first?.label, "Tibo 暗示")
    XCTAssertFalse(snapshot.isStale)
  }

  func testAnalysisRejectsOutOfRangeProbability() {
    let analysis = AIAnalysis(
      global24h: 140,
      global48h: 55,
      banked24h: 20,
      banked48h: 40,
      affectedUserBanked24h: nil,
      confidence: "high",
      confidenceNote: "test",
      likelyWindow: "test",
      summary: "test",
      evidence: []
    )

    XCTAssertThrowsError(try analysis.validated())
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
