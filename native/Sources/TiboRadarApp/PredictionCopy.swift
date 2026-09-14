import Foundation

enum PredictionCopy {
  static func lastRefresh(
    _ date: Date,
    now: Date = Date(),
    calendar: Calendar = .current
  ) -> String {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.timeZone = calendar.timeZone

    if calendar.isDate(date, inSameDayAs: now) {
      formatter.dateFormat = "HH:mm"
    } else if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
      formatter.dateFormat = "M月d日 HH:mm"
    } else {
      formatter.dateFormat = "yyyy年M月d日 HH:mm"
    }
    return "上次刷新 \(formatter.string(from: date))"
  }

  static func conditionalWindow(_ rawValue: String) -> String {
    var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let unavailableTerms = [
      "暂无集中时段", "无法可靠判断", "暂无可靠时间", "无法判断", "不能可靠判断", "不确定",
    ]
    if value.isEmpty || unavailableTerms.contains(where: value.contains) {
      return "暂无集中时段"
    }

    let prefixes = [
      "若发生，较可能落在",
      "若发生，较可能在",
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
    return value.isEmpty ? "暂无集中时段" : value
  }
}
