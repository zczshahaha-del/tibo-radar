import XCTest

@testable import TiboRadarApp

final class ProbabilityCalibrationTests: XCTestCase {
  func testExperimentalBacktestDisplaysHistoricalRange() throws {
    let result = ProbabilityCalibration.evaluate(
      bundle: bundle(status: "experimental", sampleSize: 307, beatsReference: false)
    )
    let estimate = try XCTUnwrap(result.estimate)

    XCTAssertEqual(estimate.label24h, "15–45%")
    XCTAssertEqual(estimate.label48h, "31–64%")
    XCTAssertEqual(estimate.quality, .historicalEstimate)
    XCTAssertEqual(
      result.note,
      "回放了 307 个过去时段，和旧模型接近；AI 新线索单独显示。"
    )
  }

  func testValidatedHistoricalRateRemainsClearlyHistorical() throws {
    let result = ProbabilityCalibration.evaluate(
      bundle: bundle(
        status: "validated",
        sampleSize: 308,
        beatsReference: true,
        input: "historical_rate"
      )
    )

    XCTAssertEqual(try XCTUnwrap(result.estimate).quality, .historicalEstimate)
  }

  func testValidatedAISignalBacktestIsMarkedCalibrated() throws {
    let result = ProbabilityCalibration.evaluate(
      bundle: bundle(status: "validated", sampleSize: 308, beatsReference: true)
    )
    let estimate = try XCTUnwrap(result.estimate)

    XCTAssertEqual(estimate.quality, .calibrated)
    XCTAssertEqual(estimate.sampleSize, 308)
    XCTAssertEqual(estimate.brierScore, 0.107)
  }

  func testModelWorseThanSimpleGuessIsHidden() {
    let result = ProbabilityCalibration.evaluate(
      bundle: bundle(
        status: "experimental",
        sampleSize: 307,
        beatsReference: false,
        beatsNaive: false
      )
    )

    XCTAssertNil(result.estimate)
    XCTAssertEqual(result.note, "当前模型没有比简单猜测更准，所以暂时不显示数字。")
  }

  func testInvalidRangeIsHidden() {
    var source = bundle(status: "experimental", sampleSize: 307, beatsReference: false)
    source.payloads[.forecast] = .object([
      "backtest": .object([
        "status": .string("experimental"),
        "sample_size": .number(307),
        "brier": .number(0.106),
        "better_than_naive": .bool(true),
        "better_than_rate_v2": .bool(false),
      ]),
      "probabilities": .object([
        "range_24h": .object([
          "lower": .number(0.8),
          "upper": .number(0.2),
        ])
      ]),
    ])

    XCTAssertNil(ProbabilityCalibration.evaluate(bundle: source).estimate)
  }

  private func bundle(
    status: String,
    sampleSize: Int,
    beatsReference: Bool,
    input: String = "ai_semantic_signals",
    beatsNaive: Bool = true
  ) -> SourceBundle {
    SourceBundle(
      payloads: [
        .forecast: .object([
          "backtest": .object([
            "status": .string(status),
            "input": .string(input),
            "sample_size": .number(Double(sampleSize)),
            "brier": .number(0.107),
            "better_than_naive": .bool(beatsNaive),
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
