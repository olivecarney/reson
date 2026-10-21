// Render the installer background with native typography at Retina resolution.
import AppKit

let size = NSSize(width: 640, height: 460)
let image = NSImage(size: size, flipped: true) { bounds in
    NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
    bounds.fill()

    func text(_ value: String, y: CGFloat, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        (value as NSString).draw(in: NSRect(x: 24, y: y, width: 592, height: 32),
                                withAttributes: [.font: font, .foregroundColor: color,
                                                 .paragraphStyle: paragraph])
    }
    text("Install Reson", y: 30, font: .systemFont(ofSize: 24, weight: .semibold),
         color: NSColor(calibratedWhite: 0.13, alpha: 1))
    text("Drag the app to Applications", y: 66, font: .systemFont(ofSize: 14),
         color: NSColor(calibratedWhite: 0.43, alpha: 1))

    let arrow = NSBezierPath()
    arrow.lineWidth = 2
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: 298, y: 194))
    arrow.line(to: NSPoint(x: 342, y: 194))
    arrow.move(to: NSPoint(x: 334, y: 186))
    arrow.line(to: NSPoint(x: 342, y: 194))
    arrow.line(to: NSPoint(x: 334, y: 202))
    NSColor(calibratedWhite: 0.58, alpha: 1).setStroke()
    arrow.stroke()

    text("Eject this disk, then open Reson from Applications.", y: 324,
         font: .systemFont(ofSize: 12), color: NSColor(calibratedWhite: 0.40, alpha: 1))
    return true
}
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1280, pixelsHigh: 920,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB,
                              bytesPerRow: 0, bitsPerPixel: 0)!
bitmap.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
image.draw(in: NSRect(origin: .zero, size: size))
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(
    to: URL(fileURLWithPath: CommandLine.arguments[1]))
