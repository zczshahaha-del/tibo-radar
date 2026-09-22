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
      conditionalWindow: "暂无集中时段",
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
      conditionalWindow: base.conditionalWindow,
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
      conditionalWindow: base.conditionalWindow,
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
    XCTAssertTrue(context.contains("recent_tibo_posts"))
    XCTAssertTrue(context.contains("rounded_24h"))
  }

  func testInputContextPreservesTiboPostEndingBeyondTruncatedSummary() throws {
    var source = bundle()
    source.payloads[.feed] = .object([
      "updated_at": .string("2026-09-12T03:21:00Z"),
      "events": .array([
        .object([
          "id": .string("2098612714704891959"),
          "summary": .string("Hi Astra users. A reset and a quick update on quality issues."),
          "announced_at": .string("2026-09-12T03:20:36Z"),
          "announcement_state": .string("none"),
        ])
      ]),
      "tweets": .array([
        .object([
          "id": .string("2098612714704891959"),
          "at": .string("2026-09-12T03:20:36Z"),
          "text": .string(
            "Hi Astra users. A reset and a quick update on quality issues. "
              + "More details about the fixes.\n\n"
              + "And of course, a reset is also landing by midnight today."
          ),
          "url": .string("https://x.com/thsottiaux/status/2098612714704891959"),
          "explicit_reset_claim": .bool(false),
        ])
      ]),
    ])

    let context = try AIInputBuilder.makeContext(bundle: source)
    let data = try XCTUnwrap(context.data(using: .utf8))
    let root = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    let posts = try XCTUnwrap(root["recent_tibo_posts"] as? [[String: Any]])
    let feed = try XCTUnwrap(root["recent_tibo_feed"] as? [[String: Any]])

    XCTAssertEqual(posts.first?["id"] as? String, "2098612714704891959")
    XCTAssertEqual(
      posts.first?["text"] as? String,
      "Hi Astra users. A reset and a quick update on quality issues. "
        + "More details about the fixes.\n\n"
        + "And of course, a reset is also landing by midnight today."
    )
    XCTAssertEqual(
      posts.first?["closing_paragraph"] as? String,
      "And of course, a reset is also landing by midnight today."
    )
    XCTAssertNil(posts.first?["explicit_reset_claim"])
    XCTAssertNil(feed.first?["announcement_state"])
  }

  func testInputContextIncludesLatestGeneralTiboActivityAndFreshness() throws {
    var source = bundle()
    source.payloads[.feed] = .object([
      "fetched_at": .string("2026-09-17T01:19:58Z"),
      "newest_post_at": .string("2026-09-16T23:18:15Z"),
      "signal_newest_post_at": .string("2026-09-15T15:41:39Z"),
      "stale": .bool(false),
      "events": .array([]),
      "tweets": .array([]),
      "radar_context": .array([
        .object([
          "id": .string("latest-post"),
          "at": .string("2026-09-21T06:26:15Z"),
          "text": .string("3am on a tuesday"),
          "url": .string("https://x.com/thsottiaux/status/latest-post"),
          "visibility_only": .bool(true),
        ])
      ]),
    ])

    let context = try AIInputBuilder.makeContext(bundle: source)
    let data = try XCTUnwrap(context.data(using: .utf8))
    let root = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    let freshness = try XCTUnwrap(root["tibo_feed_freshness"] as? [String: Any])
    let latestContext = try XCTUnwrap(root["recent_tibo_context"] as? [[String: Any]])

    XCTAssertEqual(freshness["newest_post_at"] as? String, "2026-09-16T23:18:15Z")
    XCTAssertEqual(freshness["signal_newest_post_at"] as? String, "2026-09-15T15:41:39Z")
    XCTAssertEqual(latestContext.first?["id"] as? String, "latest-post")
    XCTAssertEqual(
      latestContext.first?["text"] as? String,
      "3am on a tuesday"
    )
    XCTAssertEqual(
      latestContext.first?["published_at_beijing"] as? String,
      "2026-09-21T14:26:15+08:00"
    )
    XCTAssertEqual(
      latestContext.first?["published_at_pacific"] as? String,
      "2026-09-20T23:26:15-07:00"
    )
  }

  func testInputContextIncludesReplyParentAndQuotedPost() throws {
    var source = bundle()
    source.payloads[.feed] = .object([
      "events": .array([]),
      "tweets": .array([
        .object([
          "id": .string("2101352781219258527"),
          "at": .string("2026-09-19T16:48:38Z"),
          "text": .string("OK fine. But it’s also still coming in Tuesday"),
          "url": .string("https://x.com/thsottiaux/status/2101352781219258527"),
          "is_reply": .bool(true),
          "replying_to": .string("udiWertheimer"),
          "in_reply_to_tweet_id": .string("2101093319501664368"),
          "conversation_id": .string("2101093319501664368"),
          "reply_context": .object([
            "parent": .object([
              "id": .string("2101093319501664368"),
              "text": .string("you owe us a banked reset"),
              "author_handle": .string("udiWertheimer"),
            ]),
            "quoted_post": .object([
              "id": .string("2099744972195131850"),
              "text": .string("This week will also be a level of ships."),
              "author_handle": .string("thsottiaux"),
            ]),
          ]),
        ])
      ]),
    ])

    let context = try AIInputBuilder.makeContext(bundle: source)
    let data = try XCTUnwrap(context.data(using: .utf8))
    let root = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    let posts = try XCTUnwrap(root["recent_tibo_posts"] as? [[String: Any]])
    let reply = try XCTUnwrap(posts.first)
    let replyContext = try XCTUnwrap(reply["reply_context"] as? [String: Any])
    let parent = try XCTUnwrap(replyContext["parent"] as? [String: Any])
    let quote = try XCTUnwrap(replyContext["quoted_post"] as? [String: Any])

    XCTAssertEqual(reply["reply_context_status"] as? String, "available")
    XCTAssertEqual(reply["replying_to"] as? String, "udiWertheimer")
    XCTAssertEqual(parent["text"] as? String, "you owe us a banked reset")
    XCTAssertEqual(quote["text"] as? String, "This week will also be a level of ships.")
  }

  func testInputMarksReplyContextMissingInsteadOfGuessing() throws {
    var source = bundle()
    source.payloads[.feed] = .object([
      "events": .array([]),
      "tweets": .array([
        .object([
          "id": .string("reply"),
          "text": .string("OK fine. It is coming Tuesday."),
          "is_reply": .bool(true),
          "in_reply_to_tweet_id": .string("parent"),
        ])
      ]),
    ])

    let context = try AIInputBuilder.makeContext(bundle: source)

    XCTAssertTrue(context.contains("\"reply_context_status\":\"missing\""))
  }

  func testSnapshotOrdersEvidenceByVerifiedSourceDate() throws {
    let oldURL = "https://x.com/thsottiaux/status/old"
    let newURL = "https://x.com/thsottiaux/status/new"
    var source = bundle()
    source.payloads[.feed] = .object([
      "fetched_at": .string("2026-09-17T01:19:58Z"),
      "events": .array([]),
      "tweets": .array([
        .object([
          "id": .string("new"),
          "at": .string("2026-09-16T23:18:15Z"),
          "text": .string("Newer public source"),
          "url": .string(newURL),
        ]),
        .object([
          "id": .string("old"),
          "at": .string("2026-09-11T06:39:40Z"),
          "text": .string("Older background source"),
          "url": .string(oldURL),
        ]),
      ]),
    ])
    let analysis = makeAnalysis(evidence: [
      AIAnalysisEvidence(
        label: "旧背景",
        detail: "较早的长期立场。",
        category: "context",
        sourceURL: oldURL
      ),
      AIAnalysisEvidence(
        label: "无日期依据",
        detail: "来源没有可验证时间。",
        category: "context",
        sourceURL: nil
      ),
      AIAnalysisEvidence(
        label: "最新动态",
        detail: "最近仍然活跃，但没有新的重置预告。",
        category: "negative",
        sourceURL: newURL
      ),
    ])

    let snapshot = try analysis.validated().snapshot(
      bundle: source,
      now: ISO8601DateFormatter().date(from: "2026-09-17T02:00:00Z")!
    )

    XCTAssertEqual(snapshot.evidence.map(\.label), ["最新动态", "旧背景", "无日期依据"])
    XCTAssertEqual(
      snapshot.evidence.first?.sourceDate,
      ISO8601DateFormatter().date(from: "2026-09-16T23:18:15Z")
    )
    XCTAssertNil(snapshot.evidence.last?.sourceDate)
  }

  func testEvidenceFromOlderSnapshotDecodesWithoutSourceDate() throws {
    let data = try XCTUnwrap(
      """
      {
        "id": "old-evidence",
        "label": "旧快照依据",
        "detail": "旧版本没有来源日期字段。",
        "category": "context",
        "delta": 0
      }
      """.data(using: .utf8)
    )

    let evidence = try JSONDecoder().decode(Evidence.self, from: data)

    XCTAssertNil(evidence.sourceDate)
  }

  private func makeAnalysis(evidence: [AIAnalysisEvidence]? = nil) -> AIAnalysis {
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
      conditionalWindow: "暂无集中时段",
      summary: "未来两天仍可能突发重置，但目前没有明确预告。",
      evidence: evidence ?? [
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
          "tweets": .array([]),
        ]),
      ],
      cacheFallbacks: [],
      errors: []
    )
  }
}
