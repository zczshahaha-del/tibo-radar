import Foundation

struct ProbabilityCalibrationResult: Equatable, Sendable {
  let estimate: ProbabilityEstimate?
  let note: String
}

enum ProbabilityCalibration {
  static func evaluate(bundle: SourceBundle) -> ProbabilityCalibrationResult {
    guard let forecast = bundle.payloads[.forecast]?.objectValue,
      let backtest = forecast.object("backtest")
    else {
      return unavailable("没有拿到历史回放数据，所以暂时无法估计。")
    }

    guard let sampleSize = backtest.int("sample_size"), sampleSize >= 100 else {
      return unavailable("可检查的历史时段太少，所以暂时无法估计。")
    }
    guard backtest.bool("better_than_naive") == true else {
      return unavailable("当前模型没有比简单猜测更准，所以暂时不显示数字。")
    }
    guard let brierScore = backtest.number("brier"), brierScore >= 0, brierScore <= 1,
      let probabilities = forecast.object("probabilities"),
      let range24h = probabilities.object("range_24h"),
      let range48h = probabilities.object("range_48h"),
      let lower24h = percent(range24h.number("lower")),
      let upper24h = percent(range24h.number("upper")),
      let lower48h = percent(range48h.number("lower")),
      let upper48h = percent(range48h.number("upper")),
      lower24h <= upper24h,
      lower48h <= upper48h
    else {
      return unavailable("历史估计数据不完整，所以暂时不显示数字。")
    }

    let isCalibrated = backtest.string("status") == "validated"
      && backtest.string("input") == "ai_semantic_signals"
      && backtest.bool("better_than_rate_v2") == true
    let quality: ProbabilityQuality = isCalibrated ? .calibrated : .historicalEstimate
    let comparison = backtest.bool("better_than_rate_v2") == true
      ? "比旧模型更准"
      : "和旧模型接近"

    return ProbabilityCalibrationResult(
      estimate: ProbabilityEstimate(
        lower24h: lower24h,
        upper24h: upper24h,
        lower48h: lower48h,
        upper48h: upper48h,
        sampleSize: sampleSize,
        brierScore: brierScore,
        quality: quality
      ),
      note: "回放了 \(sampleSize) 个过去时段，\(comparison)；AI 新线索单独显示。"
    )
  }

  private static func unavailable(_ note: String) -> ProbabilityCalibrationResult {
    ProbabilityCalibrationResult(estimate: nil, note: note)
  }

  private static func percent(_ value: Double?) -> Int? {
    guard let value, value >= 0, value <= 1 else { return nil }
    return Int((value * 100).rounded())
  }
}
