import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
  fputs("usage: GenerateIcon.swift OUTPUT.iconset\n", stderr)
  exit(2)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(
  at: outputDirectory,
  withIntermediateDirectories: true
)

let variants: [(String, Int)] = [
  ("icon_16x16.png", 16),
  ("icon_16x16@2x.png", 32),
  ("icon_32x32.png", 32),
  ("icon_32x32@2x.png", 64),
  ("icon_128x128.png", 128),
  ("icon_128x128@2x.png", 256),
  ("icon_256x256.png", 256),
  ("icon_256x256@2x.png", 512),
  ("icon_512x512.png", 512),
  ("icon_512x512@2x.png", 1024),
]

func drawIcon(size: Int) throws -> Data {
  guard
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: size,
      pixelsHigh: size,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap)
  else {
    throw CocoaError(.fileWriteUnknown)
  }

  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = context
  context.imageInterpolation = .high

  let side = CGFloat(size)
  let inset = side * 0.055
  let rect = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
  let background = NSBezierPath(roundedRect: rect, xRadius: side * 0.22, yRadius: side * 0.22)
  let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.025, green: 0.075, blue: 0.065, alpha: 1),
    NSColor(calibratedRed: 0.035, green: 0.16, blue: 0.11, alpha: 1),
  ])!
  gradient.draw(in: background, angle: -45)

  let center = NSPoint(x: side * 0.5, y: side * 0.48)
  let mint = NSColor(calibratedRed: 0.32, green: 0.96, blue: 0.55, alpha: 1)
  for factor in [0.12, 0.23, 0.34] as [CGFloat] {
    let radius = side * factor
    let ring = NSBezierPath(
      ovalIn: NSRect(
        x: center.x - radius,
        y: center.y - radius,
        width: radius * 2,
        height: radius * 2
      ))
    ring.lineWidth = max(1, side * 0.018)
    mint.withAlphaComponent(0.88).setStroke()
    ring.stroke()
  }

  let sweep = NSBezierPath()
  sweep.move(to: center)
  sweep.line(to: NSPoint(x: side * 0.76, y: side * 0.74))
  sweep.lineWidth = max(1, side * 0.025)
  sweep.lineCapStyle = .round
  mint.setStroke()
  sweep.stroke()

  let centerDot = NSBezierPath(
    ovalIn: NSRect(
      x: center.x - side * 0.035,
      y: center.y - side * 0.035,
      width: side * 0.07,
      height: side * 0.07
    ))
  mint.setFill()
  centerDot.fill()

  let signalDot = NSBezierPath(
    ovalIn: NSRect(
      x: side * 0.71,
      y: side * 0.69,
      width: side * 0.10,
      height: side * 0.10
    ))
  NSColor.white.setFill()
  signalDot.fill()

  NSGraphicsContext.restoreGraphicsState()
  guard let data = bitmap.representation(using: .png, properties: [:]) else {
    throw CocoaError(.fileWriteUnknown)
  }
  return data
}

for (filename, size) in variants {
  let data = try drawIcon(size: size)
  try data.write(to: outputDirectory.appendingPathComponent(filename), options: .atomic)
}
