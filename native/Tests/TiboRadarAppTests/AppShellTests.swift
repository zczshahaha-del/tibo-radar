import AppKit
import XCTest

@testable import TiboRadarApp

final class AppShellTests: XCTestCase {
  @MainActor
  func testPopoverControllerResizesOuterPopoverAndContent() {
    let popover = NSPopover()
    let controller = RadarPopoverController(popover: popover)
    let contentController = NSViewController()
    controller.install(contentController)

    controller.resize(to: RadarPopoverView.expandedHeight)

    XCTAssertTrue(popover.animates)
    XCTAssertEqual(popover.contentSize.width, 344)
    XCTAssertEqual(popover.contentSize.height, 575)
    XCTAssertEqual(contentController.preferredContentSize.width, 344)
    XCTAssertEqual(contentController.preferredContentSize.height, 575)
  }
}
