// Renders the Cut logo: Resources/AppIcon.iconset (for the .icns) and assets/logo.png (README).
// Usage: swift scripts/make-icon.swift
import AppKit

let out = URL(fileURLWithPath: "Resources/AppIcon.iconset")
try? FileManager.default.removeItem(at: out)
try! FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
try! FileManager.default.createDirectory(at: URL(fileURLWithPath: "assets"), withIntermediateDirectories: true)

/// A dark squircle tile with white scissors cutting along an orange dashed line.
func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let inset = s * 0.1
    let tile = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    NSGradient(colors: [NSColor(red: 0.16, green: 0.18, blue: 0.26, alpha: 1),
                        NSColor(red: 0.05, green: 0.06, blue: 0.09, alpha: 1)])!.draw(in: path, angle: -90)

    // Scissors (SF Symbol, blades point right), mirrored so they cut leftward along a dashed line.
    let accent = NSColor(red: 1.0, green: 0.55, blue: 0.35, alpha: 1)
    let y = tile.midY
    let config = NSImage.SymbolConfiguration(pointSize: tile.width * 0.36, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    let sym = NSImage(systemSymbolName: "scissors", accessibilityDescription: nil)!.withSymbolConfiguration(config)!
    let w = sym.size.width, h = sym.size.height
    let right = tile.maxX - tile.width * 0.14
    let tip = right - w                    // blade tips after mirroring

    let line = NSBezierPath()
    line.move(to: NSPoint(x: tile.minX + tile.width * 0.14, y: y))
    line.line(to: NSPoint(x: tip + w * 0.12, y: y))
    line.lineWidth = max(1, tile.width * 0.035)
    line.lineCapStyle = .round
    line.setLineDash([tile.width * 0.045, tile.width * 0.06], count: 2, phase: 0)
    accent.setStroke()
    line.stroke()

    NSGraphicsContext.saveGraphicsState()
    let flip = NSAffineTransform()
    flip.translateX(by: right + tip, yBy: 0)
    flip.scaleX(by: -1, yBy: 1)
    flip.concat()
    sym.draw(in: NSRect(x: tip, y: y - h / 2, width: w, height: h))
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try! render(512).write(to: URL(fileURLWithPath: "assets/logo.png"))
