// Draws Fetch's app icon (dark rounded square, white arrow into a tray) into Resources/AppIcon.icns.
// Run: swift scripts/make-icon.swift
import AppKit

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024
    // macOS icon grid: 824pt body centered on a 1024 canvas.
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(starting: NSColor(white: 0.30, alpha: 1), ending: NSColor(white: 0.13, alpha: 1))!.draw(in: shape, angle: -90)
    NSColor(white: 1, alpha: 0.16).setStroke()
    shape.lineWidth = max(1, 6 * s)
    shape.stroke()

    // Down arrow dropping into a tray.
    NSColor.white.setStroke()
    let arrow = NSBezierPath()
    arrow.lineWidth = 64 * s
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: 512 * s, y: 730 * s))
    arrow.line(to: NSPoint(x: 512 * s, y: 400 * s))
    arrow.move(to: NSPoint(x: 372 * s, y: 530 * s))
    arrow.line(to: NSPoint(x: 512 * s, y: 390 * s))
    arrow.line(to: NSPoint(x: 652 * s, y: 530 * s))
    arrow.stroke()
    NSColor(white: 1, alpha: 0.5).setStroke()
    let tray = NSBezierPath()
    tray.lineWidth = 48 * s
    tray.lineCapStyle = .round
    tray.lineJoinStyle = .round
    tray.move(to: NSPoint(x: 300 * s, y: 380 * s))
    tray.line(to: NSPoint(x: 300 * s, y: 290 * s))
    tray.line(to: NSPoint(x: 724 * s, y: 290 * s))
    tray.line(to: NSPoint(x: 724 * s, y: 380 * s))
    tray.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let out = root.appendingPathComponent("Resources/AppIcon.icns")
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try! p.run()
p.waitUntilExit()
try! render(512).write(to: root.appendingPathComponent("Resources/AppIcon-preview.png"))
print(p.terminationStatus == 0 ? "wrote \(out.path)" : "iconutil failed")
