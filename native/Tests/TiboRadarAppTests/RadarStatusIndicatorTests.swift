import AppKit
import Combine
import XCTest

@testable import TiboRadarApp

final class RadarStatusIndicatorTests: XCTestCase {
  func testProbabilityBandsIncludeBoundaryValues() {
    for value in [0, 15, 39] {
      XCTAssertEqual(RadarIndicatorState(probability: value).level, .low)
    }
    for value in [40, 65, 69] {
      XCTAssertEqual(RadarIndicatorState(probability: value).level, .medium)
    }
    for value in [70, 79, 80, 92, 100] {
      XCTAssertEqual(RadarIndicatorState(probability: value).level, .high)
    }
  }

  func testMissingOrInvalidResultsAreGrayWhileStaleResultsKeepTheirColor() {
    for value: Int? in [nil, -1, 101] {
      XCTAssertEqual(RadarIndicatorState(probability: value).level, .unavailable)
    }
    let stale = RadarIndicatorState(probability: 47, isStale: true)
    XCTAssertEqual(stale.level, .medium)
    XCTAssertTrue(stale.toolTip.contains("来源或刷新异常"))
    XCTAssertTrue(stale.toolTip.contains("47%"))
  }

  func testToolTipExplainsColorAndCurrentProbability() {
    XCTAssertTrue(RadarIndicatorState(probability: 25).toolTip.contains("25% · 低概率 · 绿色"))
    XCTAssertTrue(RadarIndicatorState(probability: 60).toolTip.contains("60% · 中等概率 · 黄色"))
    XCTAssertTrue(RadarIndicatorState(probability: 92).toolTip.contains("92% · 高概率 · 红色"))
  }

  @MainActor
  func testMenuBarUsesColoredNonTemplateSymbols() throws {
    for probability in [25, 60, 70, 92] {
      let image = try XCTUnwrap(RadarIndicatorState(probability: probability).makeImage())
      XCTAssertFalse(image.isTemplate)
      let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
      var red = 0.0
      var green = 0.0
      var blue = 0.0
      var visible = 0
      for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
          guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
            color.alphaComponent > 0.5
          else { continue }
          red += color.redComponent
          green += color.greenComponent
          blue += color.blueComponent
          visible += 1
        }
      }
      XCTAssertGreaterThan(visible, 0)
      if probability == 25 {
        XCTAssertGreaterThan(green, red)
        XCTAssertGreaterThan(green, blue)
      } else if probability == 60 {
        XCTAssertGreaterThan(red, blue)
        XCTAssertGreaterThan(green, blue)
      } else {
        XCTAssertGreaterThan(red, green)
        XCTAssertGreaterThan(red, blue)
      }
      if let directory = ProcessInfo.processInfo.environment["TIBO_RADAR_STATUS_ICON_RENDER_DIR"] {
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(
          to: URL(fileURLWithPath: directory).appendingPathComponent("radar-\(probability).png"),
          options: .atomic
        )
      }
    }
  }

  @MainActor
  func testStatusPresenterUpdatesWhilePopoverIsClosedAndKeepsClickAction() throws {
    let states = CurrentValueSubject<RadarIndicatorState, Never>(RadarIndicatorState(probability: 25))
    let button = NSButton()
    let target = NSObject()
    let action = NSSelectorFromString("openRadar:")
    button.target = target
    button.action = action
    let presenter = RadarStatusItemPresenter(button: button, states: states.eraseToAnyPublisher())

    XCTAssertTrue(button.toolTip?.contains("绿色") == true)
    states.send(RadarIndicatorState(probability: 60))
    XCTAssertTrue(button.toolTip?.contains("黄色") == true)
    states.send(RadarIndicatorState(probability: 92))
    XCTAssertTrue(button.toolTip?.contains("红色") == true)
    states.send(RadarIndicatorState(probability: 47, isStale: true))
    XCTAssertTrue(button.toolTip?.contains("黄色") == true)
    XCTAssertTrue(button.toolTip?.contains("来源或刷新异常") == true)
    states.send(RadarIndicatorState(probability: nil))
    XCTAssertTrue(button.toolTip?.contains("灰色") == true)
    XCTAssertTrue(button.target === target)
    XCTAssertEqual(button.action, action)
    XCTAssertFalse(try XCTUnwrap(button.image).isTemplate)
    withExtendedLifetime(presenter) {}
  }
}
