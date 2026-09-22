import AppKit
import SwiftUI
import XCTest

@testable import TiboRadarApp

final class AppShellTests: XCTestCase {
  func testApplicationRunsAsMenuBarOnlyAccessory() {
    XCTAssertEqual(TiboRadarApplication.activationPolicy, .accessory)
  }

  @MainActor
  func testPopoverControllerUsesPopoverAsTheOnlySizeOwner() {
    let popover = NSPopover()
    let controller = RadarPopoverController(popover: popover)
    let contentController = NSViewController()
    contentController.preferredContentSize = NSSize(width: 111, height: 222)
    controller.install(contentController)

    controller.resize(to: RadarPopoverView.fallbackExpandedHeight)

    XCTAssertFalse(popover.animates)
    XCTAssertEqual(popover.behavior, .transient)
    XCTAssertEqual(popover.contentSize.width, 344)
    XCTAssertEqual(popover.contentSize.height, 640)
    XCTAssertEqual(contentController.preferredContentSize.width, 111)
    XCTAssertEqual(contentController.preferredContentSize.height, 222)
  }

  @MainActor
  func testHostingControllerDoesNotGenerateCompetingSizeConstraints() {
    let popover = NSPopover()
    let controller = RadarPopoverController(popover: popover)
    let hostingController = NSHostingController(rootView: EmptyView())

    controller.installHostingController(hostingController)

    XCTAssertTrue(hostingController.sizingOptions.isEmpty)
    XCTAssertTrue(popover.contentViewController === hostingController)
  }
}
