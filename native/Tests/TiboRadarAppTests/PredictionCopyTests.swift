import XCTest

@testable import TiboRadarApp

final class PredictionCopyTests: XCTestCase {
  func testLastRefreshShowsClockTimeForToday() throws {
    let calendar = testCalendar()
    let now = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 18))
    )
    let refreshedAt = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 15, minute: 26))
    )

    XCTAssertEqual(
      PredictionCopy.lastRefresh(refreshedAt, now: now, calendar: calendar),
      "上次刷新 15:26"
    )
  }

  func testLastRefreshIncludesDateWhenNotToday() throws {
    let calendar = testCalendar()
    let now = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 18))
    )
    let refreshedAt = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 9, day: 12, hour: 23, minute: 8))
    )

    XCTAssertEqual(
      PredictionCopy.lastRefresh(refreshedAt, now: now, calendar: calendar),
      "上次刷新 9月12日 23:08"
    )
  }

  func testUnavailableTimeUsesPlainLanguage() {
    XCTAssertEqual(
      PredictionCopy.conditionalWindow("若发生，无法可靠判断具体时间"),
      "暂无集中时段"
    )
    XCTAssertEqual(PredictionCopy.conditionalWindow("暂无集中时段"), "暂无集中时段")
  }

  func testVerbosePrefixIsRemovedButTimeIsKept() {
    XCTAssertEqual(
      PredictionCopy.conditionalWindow("若发生，较可能落在北京时间 08:00–12:00"),
      "北京时间 08:00–12:00"
    )
  }

  private func testCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)!
    return calendar
  }
}
