import XCTest

@testable import TiboRadarApp

final class PredictionCopyTests: XCTestCase {
  func testUnavailableTimeUsesPlainLanguage() {
    XCTAssertEqual(
      PredictionCopy.likelyTime("若发生，无法可靠判断具体时间"),
      "暂时算不出"
    )
    XCTAssertEqual(PredictionCopy.likelyTime("暂无可靠时间"), "暂时算不出")
  }

  func testVerbosePrefixIsRemovedButTimeIsKept() {
    XCTAssertEqual(
      PredictionCopy.likelyTime("若发生，最可能落在北京时间 08:00–12:00"),
      "北京时间 08:00–12:00"
    )
  }
}
