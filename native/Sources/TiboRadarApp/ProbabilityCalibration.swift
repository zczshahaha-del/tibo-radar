import Foundation

struct ProbabilityCalibrationResult: Equatable, Sendable {
  let range: CalibratedProbabilityRange?
  let note: String
}

enum ProbabilityCalibration {
  static func evaluate(bundle: SourceBundle) -> ProbabilityCalibrationResult {
    guard let forecast = bundle.payloads[.forecast]?.objectValue,
      let backtest = forecast.object("backtest")
    else {
      return unavailable("还没有足够的历史预测记录，所以先不显示数字。")
    }

    guard backtest.string("status") == "validated" else {
      return unavailable("拿历史数据试算后，结果还不够准，所以先不显示数字。")
    }
    guard let sampleSize = backtest.int("sample_size"), sampleSize >= 100 else {
      return unavailable("可检查的历史预测太少，所以先不显示数字。")
    }
    guard backtest.string("input") == "ai_semantic_signals" else {
      return unavailable("当前试算还没把 AI 识别的线索算进去，所以先不显示数字。")
    }
    guard backtest.bool("better_than_naive") == true,
      backtest.bool("better_than_rate_v2") == true
    else {
      return unavailable("试算结果没有比简单猜测更准，所以先不显示数字。")
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
      return unavailable("历史试算数据不完整，所以先不显示数字。")
    }

    return ProbabilityCalibrationResult(
      range: CalibratedProbabilityRange(
        lower24h: lower24h,
        upper24h: upper24h,
        lower48h: lower48h,
        upper48h: upper48h,
        sampleSize: sampleSize,
        brierScore: brierScore
      ),
      note: "回放了 \(sampleSize) 个过去时段并达到要求，只显示概率范围。"
    )
  }

  private static func unavailable(_ note: String) -> ProbabilityCalibrationResult {
    ProbabilityCalibrationResult(range: nil, note: note)
  }

  private static func percent(_ value: Double?) -> Int? {
    guard let value, value >= 0, value <= 1 else { return nil }
    return Int((value * 100).rounded())
  }
}
