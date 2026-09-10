import Foundation

enum PredictionCopy {
  static func likelyTime(_ rawValue: String) -> String {
    var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let unavailableTerms = [
      "无法可靠判断", "暂无可靠时间", "无法判断", "不能可靠判断", "不确定",
    ]
    if value.isEmpty || unavailableTerms.contains(where: value.contains) {
      return "暂时算不出"
    }

    let prefixes = [
      "若发生，最可能落在",
      "若发生,最可能落在",
      "若发生，最可能在",
      "最可能落在",
      "最可能在",
    ]
    for prefix in prefixes where value.hasPrefix(prefix) {
      value.removeFirst(prefix.count)
      break
    }
    value = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? "暂时算不出" : value
  }
}
