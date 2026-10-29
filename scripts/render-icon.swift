// Renders Resources/AppIcon.svg to PNG with a drop shadow, using AppKit's own SVG support.
// ImageMagick's fallback renderer ignored the gradients and produced a black square.
// Usage: swift scripts/render-icon.swift <input.svg> <output.png> <pixels>
import AppKit

let args = CommandLine.arguments
guard args.count == 4, let pixels = Int(args[3]), let svg = NSImage(contentsOfFile: args[1]) else {
    FileHandle.standardError.write("usage: render-icon.swift <input.svg> <output.png> <pixels>\n".data(using: .utf8)!)
    exit(1)
}

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let scale = CGFloat(pixels) / 1024

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let shadow = NSShadow()
shadow.shadowOffset = NSSize(width: 0, height: -12 * scale)
shadow.shadowBlurRadius = 28 * scale
shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
shadow.set()
svg.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
NSGraphicsContext.restoreGraphicsState()

try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
