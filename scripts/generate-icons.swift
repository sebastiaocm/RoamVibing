#!/usr/bin/env swift

import AppKit
import Foundation

let outputDirectory = URL(
    fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources",
    isDirectory: true
)
let iconsetDirectory = outputDirectory.appendingPathComponent("RoamVibingIcon.iconset", isDirectory: true)

try? FileManager.default.removeItem(at: iconsetDirectory)
try FileManager.default.createDirectory(at: iconsetDirectory, withIntermediateDirectories: true)

let iconSpecs: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for spec in iconSpecs {
    let data = pngData(pixels: spec.pixels) { rect in
        drawAppIcon(in: rect)
    }
    try data.write(to: iconsetDirectory.appendingPathComponent(spec.name))
}

try pngData(pixels: 64) { rect in
    drawStatusTemplate(in: rect, active: false)
}.write(to: outputDirectory.appendingPathComponent("RoamVibingStatusTemplateOff.png"))

try pngData(pixels: 64) { rect in
    drawStatusTemplate(in: rect, active: true)
}.write(to: outputDirectory.appendingPathComponent("RoamVibingStatusTemplateOn.png"))

func pngData(pixels: Int, draw: (NSRect) -> Void) -> Data {
    guard let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Could not create bitmap representation")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
    NSGraphicsContext.current?.imageInterpolation = .high
    NSGraphicsContext.current?.shouldAntialias = true
    draw(NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()

    guard let data = representation.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode PNG")
    }
    return data
}

func drawAppIcon(in rect: NSRect) {
    let unit = rect.width / 1024
    func scaled(_ value: CGFloat) -> CGFloat { value * unit }
    func box(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSRect {
        NSRect(x: scaled(x), y: scaled(y), width: scaled(width), height: scaled(height))
    }

    let background = NSBezierPath(
        roundedRect: box(64, 64, 896, 896),
        xRadius: scaled(218),
        yRadius: scaled(218)
    )
    NSGraphicsContext.saveGraphicsState()
    background.addClip()
    NSGradient(colors: [
        NSColor(srgbRed: 0.07, green: 0.09, blue: 0.14, alpha: 1),
        NSColor(srgbRed: 0.08, green: 0.25, blue: 0.25, alpha: 1),
        NSColor(srgbRed: 0.04, green: 0.09, blue: 0.10, alpha: 1)
    ])?.draw(in: background, angle: -45)
    NSGraphicsContext.restoreGraphicsState()

    NSColor(srgbRed: 0.95, green: 0.70, blue: 0.43, alpha: 1).setFill()
    NSBezierPath(ovalIn: box(426, 632, 172, 172)).fill()

    NSColor(srgbRed: 0.18, green: 0.83, blue: 0.75, alpha: 1).setFill()
    let hoodie = NSBezierPath()
    hoodie.move(to: NSPoint(x: scaled(354), y: scaled(548)))
    hoodie.curve(
        to: NSPoint(x: scaled(670), y: scaled(548)),
        controlPoint1: NSPoint(x: scaled(374), y: scaled(650)),
        controlPoint2: NSPoint(x: scaled(650), y: scaled(650))
    )
    hoodie.line(to: NSPoint(x: scaled(670), y: scaled(466)))
    hoodie.line(to: NSPoint(x: scaled(354), y: scaled(466)))
    hoodie.close()
    hoodie.fill()

    NSColor(srgbRed: 0.06, green: 0.46, blue: 0.43, alpha: 1).setFill()
    let hair = NSBezierPath()
    hair.move(to: NSPoint(x: scaled(304), y: scaled(632)))
    hair.curve(
        to: NSPoint(x: scaled(720), y: scaled(632)),
        controlPoint1: NSPoint(x: scaled(360), y: scaled(760)),
        controlPoint2: NSPoint(x: scaled(664), y: scaled(760))
    )
    hair.curve(
        to: NSPoint(x: scaled(598), y: scaled(684)),
        controlPoint1: NSPoint(x: scaled(682), y: scaled(666)),
        controlPoint2: NSPoint(x: scaled(640), y: scaled(682))
    )
    hair.curve(
        to: NSPoint(x: scaled(426), y: scaled(684)),
        controlPoint1: NSPoint(x: scaled(568), y: scaled(736)),
        controlPoint2: NSPoint(x: scaled(456), y: scaled(736))
    )
    hair.curve(
        to: NSPoint(x: scaled(304), y: scaled(632)),
        controlPoint1: NSPoint(x: scaled(384), y: scaled(682)),
        controlPoint2: NSPoint(x: scaled(342), y: scaled(666))
    )
    hair.close()
    hair.fill()

    drawLaptop(in: rect, scaled: scaled, box: box)

    NSColor(srgbRed: 0.95, green: 0.70, blue: 0.43, alpha: 1).setFill()
    NSBezierPath(ovalIn: box(274, 364, 64, 64)).fill()
    NSBezierPath(ovalIn: box(686, 364, 64, 64)).fill()
}

func drawLaptop(
    in rect: NSRect,
    scaled: (CGFloat) -> CGFloat,
    box: (CGFloat, CGFloat, CGFloat, CGFloat) -> NSRect
) {
    NSColor(srgbRed: 0.90, green: 0.93, blue: 0.94, alpha: 1).setFill()
    NSBezierPath(roundedRect: box(232, 266, 560, 328), xRadius: scaled(44), yRadius: scaled(44)).fill()

    let screen = NSBezierPath(roundedRect: box(276, 322, 472, 214), xRadius: scaled(28), yRadius: scaled(28))
    NSGraphicsContext.saveGraphicsState()
    screen.addClip()
    NSGradient(colors: [
        NSColor(srgbRed: 0.06, green: 0.09, blue: 0.12, alpha: 1),
        NSColor(srgbRed: 0.09, green: 0.15, blue: 0.17, alpha: 1)
    ])?.draw(in: screen, angle: -20)
    NSGraphicsContext.restoreGraphicsState()

    drawCodeStroke(points: [
        NSPoint(x: scaled(408), y: scaled(446)),
        NSPoint(x: scaled(336), y: scaled(390)),
        NSPoint(x: scaled(408), y: scaled(334))
    ], color: NSColor(srgbRed: 0.49, green: 0.83, blue: 0.99, alpha: 1), width: scaled(35))

    drawCodeStroke(points: [
        NSPoint(x: scaled(616), y: scaled(334)),
        NSPoint(x: scaled(688), y: scaled(390)),
        NSPoint(x: scaled(616), y: scaled(446))
    ], color: NSColor(srgbRed: 0.49, green: 0.83, blue: 0.99, alpha: 1), width: scaled(35))

    drawCodeStroke(points: [
        NSPoint(x: scaled(548), y: scaled(452)),
        NSPoint(x: scaled(478), y: scaled(324))
    ], color: NSColor(srgbRed: 0.65, green: 0.95, blue: 0.82, alpha: 1), width: scaled(35))

    NSColor(srgbRed: 0.80, green: 0.84, blue: 0.87, alpha: 1).setFill()
    let base = NSBezierPath()
    base.move(to: NSPoint(x: scaled(190), y: scaled(278)))
    base.line(to: NSPoint(x: scaled(834), y: scaled(278)))
    base.line(to: NSPoint(x: scaled(906), y: scaled(184)))
    base.line(to: NSPoint(x: scaled(118), y: scaled(184)))
    base.close()
    base.fill()

    NSColor(srgbRed: 0.58, green: 0.64, blue: 0.72, alpha: 1).setFill()
    let trackpad = NSBezierPath()
    trackpad.move(to: NSPoint(x: scaled(424), y: scaled(244)))
    trackpad.line(to: NSPoint(x: scaled(600), y: scaled(244)))
    trackpad.line(to: NSPoint(x: scaled(626), y: scaled(208)))
    trackpad.line(to: NSPoint(x: scaled(398), y: scaled(208)))
    trackpad.close()
    trackpad.fill()
}

func drawStatusTemplate(in rect: NSRect, active: Bool) {
    let scale = rect.width / 64
    NSColor.black.setFill()
    drawCoderMark(scale: scale, active: active)
}

func drawCoderMark(scale: CGFloat, active: Bool) {
    func value(_ point: CGFloat) -> CGFloat { point * scale }
    func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSRect {
        NSRect(x: value(x), y: value(y), width: value(width), height: value(height))
    }

    NSBezierPath(ovalIn: rect(25, 42, 14, 14)).fill()

    let body = NSBezierPath()
    body.move(to: NSPoint(x: value(18), y: value(32)))
    body.curve(
        to: NSPoint(x: value(46), y: value(32)),
        controlPoint1: NSPoint(x: value(20), y: value(41)),
        controlPoint2: NSPoint(x: value(44), y: value(41))
    )
    body.line(to: NSPoint(x: value(46), y: value(27)))
    body.line(to: NSPoint(x: value(18), y: value(27)))
    body.close()
    body.fill()

    NSBezierPath(roundedRect: rect(12, 18, 40, 22), xRadius: value(4), yRadius: value(4)).fill()

    let base = NSBezierPath()
    base.move(to: NSPoint(x: value(8), y: value(18)))
    base.line(to: NSPoint(x: value(56), y: value(18)))
    base.line(to: NSPoint(x: value(60), y: value(12)))
    base.line(to: NSPoint(x: value(4), y: value(12)))
    base.close()
    base.fill()

    if active {
        NSBezierPath(ovalIn: rect(48, 46, 10, 10)).fill()
    }
}

func drawCodeStroke(points: [NSPoint], color: NSColor, width: CGFloat) {
    guard let first = points.first else {
        return
    }

    color.setStroke()
    let path = NSBezierPath()
    path.lineWidth = width
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.move(to: first)
    for point in points.dropFirst() {
        path.line(to: point)
    }
    path.stroke()
}
