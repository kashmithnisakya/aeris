// Draws the 1024x1024 app icon: blue rounded square with a white AC symbol.
// Usage: swift scripts/make-icon.swift out.png
import AppKit

let out = CommandLine.arguments.dropFirst().first ?? "icon-1024.png"
let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let inset: CGFloat = 100
let rect = NSRect(x: inset, y: inset, width: CGFloat(size) - inset * 2, height: CGFloat(size) - inset * 2)
let path = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
NSGradient(starting: NSColor(red: 0.33, green: 0.66, blue: 1.0, alpha: 1),
           ending: NSColor(red: 0.13, green: 0.38, blue: 0.92, alpha: 1))!.draw(in: path, angle: -90)

let config = NSImage.SymbolConfiguration(pointSize: 420, weight: .regular)
    .applying(.init(paletteColors: [.white]))
if let symbol = NSImage(systemSymbolName: "air.conditioner.horizontal.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let s = symbol.size
    symbol.draw(in: NSRect(x: (CGFloat(size) - s.width) / 2, y: (CGFloat(size) - s.height) / 2,
                           width: s.width, height: s.height))
}
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
