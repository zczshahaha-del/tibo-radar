import AppKit
import Combine

enum RadarIndicatorLevel: Equatable, Sendable {
  case low
  case medium
  case high
  case unavailable

  @MainActor
  var color: NSColor {
    switch self {
    case .low: .systemGreen
    case .medium: .systemYellow
    case .high: .systemRed
    case .unavailable: .systemGray
    }
  }

  var label: String {
    switch self {
    case .low: "低概率 · 绿色"
    case .medium: "中等概率 · 黄色"
    case .high: "高概率 · 红色"
    case .unavailable: "暂无有效预测 · 灰色"
    }
  }
}

struct RadarIndicatorState: Equatable, Sendable {
  let probability: Int?
  let isStale: Bool

  init(probability: Int?, isStale: Bool = false) {
    self.probability = probability
    self.isStale = isStale
  }

  init(snapshot: PredictionSnapshot?) {
    self.init(probability: snapshot?.combined24h.likely, isStale: snapshot?.isStale ?? false)
  }

  var level: RadarIndicatorLevel {
    guard !isStale, let probability, (0...100).contains(probability) else { return .unavailable }
    switch probability {
    case ..<40: return .low
    case ..<70: return .medium
    default: return .high
    }
  }

  var toolTip: String {
    if level == .unavailable {
      if isStale, let probability {
        return "Tibo Radar：预测已过期 · 灰色（上次 24 小时综合概率 \(probability)%）"
      }
      return "Tibo Radar：\(level.label)"
    }
    return "Tibo Radar：24 小时综合概率 \(probability!)% · \(level.label)"
  }

  @MainActor
  var color: NSColor { level.color }

  @MainActor
  func makeImage() -> NSImage? {
    let symbol = NSImage(systemSymbolName: "dot.radiowaves.up.forward", accessibilityDescription: toolTip)
    let image = symbol?.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [color]))
    image?.isTemplate = false
    return image
  }
}

@MainActor
final class RadarStatusItemPresenter {
  private weak var button: NSButton?
  private var subscription: AnyCancellable?

  init(button: NSButton, states: AnyPublisher<RadarIndicatorState, Never>) {
    self.button = button
    subscription = states.removeDuplicates().sink { [weak self] state in
      self?.button?.image = state.makeImage()
      self?.button?.toolTip = state.toolTip
      self?.button?.setAccessibilityLabel(state.toolTip)
    }
  }
}
