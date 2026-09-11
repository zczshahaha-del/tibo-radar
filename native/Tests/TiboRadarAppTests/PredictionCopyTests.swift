import XCTest

@testable import TiboRadarApp

final class PredictionCopyTests: XCTestCase {
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
}
