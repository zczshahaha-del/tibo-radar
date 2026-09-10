import SwiftUI

@main
struct TiboRadarApp: App {
  @StateObject private var model = RadarViewModel()

  var body: some Scene {
    MenuBarExtra {
      RadarPopoverView()
        .environmentObject(model)
    } label: {
      Image(systemName: "dot.radiowaves.up.forward")
        .accessibilityLabel("Tibo Radar")
    }
    .menuBarExtraStyle(.window)
  }
}
