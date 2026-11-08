// Draws the app icon: a pop-up with "Aa" on the Playful style's gradient. build.sh runs it and turns the picture
// into AppIcon.icns. Usage: swift icon.swift <output.png>
import AppKit

let CANVAS: CGFloat = 1024
// Apple's macOS icon grid: the shape fills 824 of the 1024 points, with this corner radius.
let SHAPE_INSET: CGFloat = 100
let SHAPE_RADIUS: CGFloat = 185
let TOP_COLOR = NSColor(srgbRed: 0x7B / 255.0, green: 0x5C / 255.0, blue: 0xFF / 255.0, alpha: 1)
let BOTTOM_COLOR = NSColor(srgbRed: 0xFF / 255.0, green: 0x5F / 255.0, blue: 0xA2 / 255.0, alpha: 1)
let BUBBLE = NSRect(x: 232, y: 330, width: 560, height: 400)
let BUBBLE_RADIUS: CGFloat = 96
// The bubble's tail, pointing down to the text it's about.
let TAIL = [NSPoint(x: 330, y: 340), NSPoint(x: 300, y: 236), NSPoint(x: 440, y: 340)]
let TEXT = "Aa"
let TEXT_SIZE: CGFloat = 270
let TEXT_RAISE: CGFloat = 8

let output = CommandLine.arguments[1]
let image = NSImage(size: NSSize(width: CANVAS, height: CANVAS), flipped: false) { _ in
    let shape = NSRect(x: 0, y: 0, width: CANVAS, height: CANVAS).insetBy(dx: SHAPE_INSET, dy: SHAPE_INSET)
    NSGradient(starting: TOP_COLOR, ending: BOTTOM_COLOR)!
        .draw(in: NSBezierPath(roundedRect: shape, xRadius: SHAPE_RADIUS, yRadius: SHAPE_RADIUS), angle: -90)

    let bubble = NSBezierPath(roundedRect: BUBBLE, xRadius: BUBBLE_RADIUS, yRadius: BUBBLE_RADIUS)
    let tail = NSBezierPath()
    tail.move(to: TAIL[0])
    TAIL.dropFirst().forEach { tail.line(to: $0) }
    tail.close()
    bubble.append(tail)
    NSColor.white.setFill()
    bubble.fill()

    let text = NSAttributedString(string: TEXT, attributes: [
        .font: NSFont.systemFont(ofSize: TEXT_SIZE, weight: .semibold),
        .foregroundColor: TOP_COLOR,
    ])
    let size = text.size()
    text.draw(at: NSPoint(x: BUBBLE.midX - size.width / 2, y: BUBBLE.midY - size.height / 2 + TEXT_RAISE))
    return true
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(CANVAS), pixelsHigh: Int(CANVAS), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: NSRect(x: 0, y: 0, width: CANVAS, height: CANVAS))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
