import XCTest

@testable import TiboRadarApp

final class ProbabilityCalibrationTests: XCTestCase {
  func testExperimentalBacktestNeverDisplaysProbability() {
    let result = ProbabilityCalibration.evaluate(
      bundle: bundle(status: "experimental", sampleSize: 308, beatsReference: true)
    )

    XCTAssertNil(result.range)
    XCTAssertEqual(result.note, "拿历史数据试算后，结果还不够准，所以先不显示数字。")
  }

  func testValidatedBacktestMustBeatBothBaselines() {
    let result = ProbabilityCalibration.evaluate(
      bundle: bundle(status: "validated", sampleSize: 308, beatsReference: false)
    )

    XCTAssertNil(result.range)
    XCTAssertEqual(result.note, "试算结果没有比简单猜测更准，所以先不显示数字。")
  }

  func testValidatedHistoricalRateWithoutAISignalsIsRejected() {
    let result = ProbabilityCalibration.evaluate(
      bundle: bundle(
        status: "validated",
        sampleSize: 308,
        beatsReference: true,
        input: "historical_rate"
      )
    )

    XCTAssertNil(result.range)
    XCTAssertEqual(
      result.note,
      "当前试算还没把 AI 识别的线索算进去，所以先不显示数字。"
    )
  }

  func testValidatedBacktestDisplaysRangeInsteadOfPointEstimate() throws {
    let result = ProbabilityCalibration.evaluate(
      bundle: bundle(status: "validated", sampleSize: 308, beatsReference: true)
    )
    let range = try XCTUnwrap(result.range)

    XCTAssertEqual(range.label24h, "15–45%")
    XCTAssertEqual(range.label48h, "31–64%")
    XCTAssertEqual(range.sampleSize, 308)
    XCTAssertEqual(range.brierScore, 0.107)
  }

  private func bundle(
    status: String,
    sampleSize: Int,
    beatsReference: Bool,
    input: String = "ai_semantic_signals"
  ) -> SourceBundle {
    SourceBundle(
      payloads: [
        .forecast: .object([
          "backtest": .object([
            "status": .string(status),
            "input": .string(input),
            "sample_size": .number(Double(sampleSize)),
            "brier": .number(0.107),
            "better_than_naive": .bool(true),
            "better_than_rate_v2": .bool(beatsReference),
          ]),
          "probabilities": .object([
            "range_24h": .object([
              "lower": .number(0.146),
              "upper": .number(0.448),
            ]),
            "range_48h": .object([
              "lower": .number(0.305),
              "upper": .number(0.64),
            ]),
          ]),
        ])
      ],
      cacheFallbacks: [],
      errors: []
    )
  }
}
