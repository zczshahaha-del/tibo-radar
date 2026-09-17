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
      popoverController.close(sender)
    } else {
      popoverController.show(
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
final class RadarPopoverController: NSObject, NSPopoverDelegate {
  let popover: NSPopover
  private var outsideClickMonitor: Any?

  init(popover: NSPopover = NSPopover()) {
    self.popover = popover
    super.init()
    popover.behavior = .transient
    popover.animates = false
    popover.delegate = self
  }

  func install(_ contentViewController: NSViewController) {
    popover.contentViewController = contentViewController
  }

  func resize(to height: CGFloat) {
    let size = NSSize(width: RadarPopoverView.panelWidth, height: height)
    popover.contentSize = size
    popover.contentViewController?.preferredContentSize = size
  }

  func show(
    relativeTo positioningRect: NSRect,
    of positioningView: NSView,
    preferredEdge: NSRectEdge
  ) {
    popover.show(
      relativeTo: positioningRect,
      of: positioningView,
      preferredEdge: preferredEdge
    )
    startOutsideClickMonitoring()
  }

  func close(_ sender: Any? = nil) {
    stopOutsideClickMonitoring()
    popover.performClose(sender)
  }

  func popoverDidClose(_ notification: Notification) {
    stopOutsideClickMonitoring()
  }

  private func startOutsideClickMonitoring() {
    guard outsideClickMonitor == nil else { return }
    outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown]
    ) { [weak self] _ in
      Task { @MainActor in
        self?.close()
      }
    }
  }

  private func stopOutsideClickMonitoring() {
    guard let outsideClickMonitor else { return }
    NSEvent.removeMonitor(outsideClickMonitor)
    self.outsideClickMonitor = nil
  }
}
