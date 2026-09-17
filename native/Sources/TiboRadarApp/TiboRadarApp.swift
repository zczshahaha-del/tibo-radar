import AppKit
import SwiftUI

@main
struct TiboRadarApp: App {
  @NSApplicationDelegateAdaptor(TiboRadarAppDelegate.self) private var appDelegate

  var body: some Scene {
    Settings {
      EmptyView()
    }
  }
}

@MainActor
final class TiboRadarAppDelegate: NSObject, NSApplicationDelegate {
  private let popoverController = RadarPopoverController()
  private var statusItem: NSStatusItem?
  private var model: RadarViewModel?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let model = RadarViewModel()
    self.model = model

    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    self.statusItem = statusItem
    if let button = statusItem.button {
      button.image = NSImage(
        systemSymbolName: "dot.radiowaves.up.forward",
        accessibilityDescription: "Tibo Radar"
      )
      button.image?.isTemplate = true
      button.target = self
      button.action = #selector(togglePopover(_:))
      button.toolTip = "Tibo Radar"
    }

    let rootView = RadarPopoverView { [weak self] height in
      self?.resizePopover(to: height)
    }
    .environmentObject(model)
    let hostingController = NSHostingController(rootView: rootView)

    popoverController.install(hostingController)
    popoverController.resize(to: RadarPopoverView.compactHeight)
  }

  @objc private func togglePopover(_ sender: Any?) {
    guard let button = statusItem?.button else { return }
    let popover = popoverController.popover
    if popover.isShown {
      popover.performClose(sender)
    } else {
      popover.show(
        relativeTo: button.bounds,
        of: button,
        preferredEdge: .minY
      )
      NSApp.activate(ignoringOtherApps: true)
    }
  }

  private func resizePopover(to height: CGFloat) {
    popoverController.resize(to: height)
  }
}

@MainActor
final class RadarPopoverController {
  let popover: NSPopover

  init(popover: NSPopover = NSPopover()) {
    self.popover = popover
    popover.behavior = .transient
    popover.animates = false
  }

  func install(_ contentViewController: NSViewController) {
    popover.contentViewController = contentViewController
  }

  func resize(to height: CGFloat) {
    let size = NSSize(width: RadarPopoverView.panelWidth, height: height)
    popover.contentSize = size
    popover.contentViewController?.preferredContentSize = size
  }
}
