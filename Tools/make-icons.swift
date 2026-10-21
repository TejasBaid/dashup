// Renders the DashUp app icons. Run: swift Tools/make-icons.swift
import AppKit

func render(size: CGFloat, inset: CGFloat, corner: CGFloat, to path: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let bg = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    NSColor(srgbRed: 0.106, green: 0.102, blue: 0.098, alpha: 1).setFill()
    NSBezierPath(roundedRect: bg, xRadius: corner, yRadius: corner).fill()

    let tan = NSColor(srgbRed: 0.788, green: 0.635, blue: 0.494, alpha: 1)
    let s = bg.width
    // Monitor: outlined rounded rectangle.
    let monitor = NSRect(x: bg.minX + s * 0.20, y: bg.minY + s * 0.42, width: s * 0.60, height: s * 0.36)
    let stroke = NSBezierPath(roundedRect: monitor.insetBy(dx: s * 0.022, dy: s * 0.022), xRadius: s * 0.045, yRadius: s * 0.045)
    stroke.lineWidth = s * 0.044
    tan.setStroke()
    stroke.stroke()
    // iPad: solid slab underneath.
    let pad = NSRect(x: bg.minX + s * 0.30, y: bg.minY + s * 0.24, width: s * 0.40, height: s * 0.10)
    tan.setFill()
    NSBezierPath(roundedRect: pad, xRadius: s * 0.03, yRadius: s * 0.03).fill()

    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

// iOS masks the icon itself, so fill the square.
render(size: 1024, inset: 0, corner: 0, to: "Pad/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png")
// macOS icons carry their own rounded shape and margin.
render(size: 1024, inset: 100, corner: 185, to: "Mac/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png")
print("icons written")
