#!/usr/bin/env swift
import AppKit

// Renders the Voice Dictator app icon to a 1024×1024 PNG per the design spec:
// macOS squircle, diagonal indigo gradient, subtle top glow + corner vignette,
// and a bold 5-bar white waveform with a soft shadow. Output path is argv[1].
// Coordinates here are AppKit's bottom-left origin; the spec's top-left values
// are converted inline (y_bottom = 1024 - y_top - height).

let size = 1024.0
let out = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "AppIcon-1024.png"

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!

let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx
let cg = ctx.cgContext
cg.interpolationQuality = .high

// --- Squircle (live area: 824×824 inset 100, corner radius 185.4) ---
let inset = 100.0, live = 824.0, radius = 185.4
let squircle = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: live, height: live),
                            xRadius: radius, yRadius: radius)

// --- Background gradient, diagonal top-left → bottom-right ---
cg.saveGState()
squircle.addClip()
let bg = NSGradient(colors: [color(0x5B7CFF), color(0x4A54E8), color(0x2E2CB8)],
                    atLocations: [0.0, 0.55, 1.0], colorSpace: .sRGB)!
// -45° points right-and-down → #5B7CFF lands in the top-left corner.
bg.draw(in: squircle, angle: -45)

// --- Top-edge inner glow: white, feathered over the top ~140px at 9% ---
let glow = NSGradient(colors: [color(0xFFFFFF, 0.09), color(0xFFFFFF, 0.0)])!
glow.draw(in: NSRect(x: inset, y: inset + live - 140, width: live, height: 140), angle: -90)

// --- Corner vignette: barely-there radial darkening at the extremes ---
let vignette = NSGradient(colors: [color(0x000000, 0.0), color(0x000000, 0.06)],
                          atLocations: [0.70, 1.0], colorSpace: .sRGB)!
let center = NSPoint(x: size / 2, y: size / 2)
vignette.draw(fromCenter: center, radius: 0, toCenter: center, radius: live * 0.72, options: [])
cg.restoreGState()

// --- Optional crisp rim hairline ---
color(0xFFFFFF, 0.12).setStroke()
squircle.lineWidth = 1
squircle.stroke()

// --- Waveform glyph: 5 white rounded bars, soft indigo shadow ---
let heights = [190.0, 330.0, 470.0, 330.0, 190.0]  // outer→inner symmetric
let barW = 60.0, gap = 52.0
let blockW = 5 * barW + 4 * gap            // 508
var x = (size - blockW) / 2                // 258
let midY = 512.0

let shadow = NSShadow()
shadow.shadowColor = color(0x1A1A4D, 0.22)
shadow.shadowBlurRadius = 18
shadow.shadowOffset = NSSize(width: 0, height: -10)  // spec (0,+10) downward in top-left space

cg.saveGState()
shadow.set()
color(0xFFFFFF).setFill()
for h in heights {
    let bar = NSBezierPath(roundedRect: NSRect(x: x, y: midY - h / 2, width: barW, height: h),
                           xRadius: barW / 2, yRadius: barW / 2)
    bar.fill()
    x += barW + gap
}
cg.restoreGState()

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("failed to encode PNG\n".utf8)); exit(1)
}
do {
    try png.write(to: URL(fileURLWithPath: out))
    print("wrote \(out)")
} catch {
    FileHandle.standardError.write(Data("write failed: \(error)\n".utf8)); exit(1)
}
