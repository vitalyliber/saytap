// Draws the background of the installer window: an arrow from the app to Applications on a light Playful
// gradient. dmg.sh runs it at 1x and 2x. Usage: swift dmg-background.swift <scale> <output.png>
import AppKit

// Keep in step with the window and icon positions in dmg.sh.
let WINDOW = NSSize(width: 640, height: 400)
let ICON_Y: CGFloat = 190
let APP_X: CGFloat = 170
let APPLICATIONS_X: CGFloat = 470
let ICON_HALF: CGFloat = 64
let ARROW_GAP: CGFloat = 26
let ARROW_WIDTH: CGFloat = 7
let ARROW_HEAD: CGFloat = 20
let ARROW_BEND: CGFloat = 26
let TOP_COLOR = NSColor(srgbRed: 0xF6 / 255.0, green: 0xF2 / 255.0, blue: 0xFF / 255.0, alpha: 1)
let BOTTOM_COLOR = NSColor(srgbRed: 0xFF / 255.0, green: 0xF0 / 255.0, blue: 0xF6 / 255.0, alpha: 1)
let PURPLE = NSColor(srgbRed: 0x7B / 255.0, green: 0x5C / 255.0, blue: 0xFF / 255.0, alpha: 1)
let PINK = NSColor(srgbRed: 0xFF / 255.0, green: 0x5F / 255.0, blue: 0xA2 / 255.0, alpha: 1)
let TEXT_COLOR = NSColor(srgbRed: 0x62 / 255.0, green: 0x5E / 255.0, blue: 0x73 / 255.0, alpha: 1)
let TITLE = "Drag Saytap into Applications"
let TITLE_SIZE: CGFloat = 17
let TITLE_FROM_TOP: CGFloat = 58

let scale = CGFloat(Double(CommandLine.arguments[1])!)
let output = CommandLine.arguments[2]
// Finder measures the icon positions from the top; drawing measures from the bottom.
let iconY = WINDOW.height - ICON_Y

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(WINDOW.width * scale), pixelsHigh: Int(WINDOW.height * scale),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = WINDOW
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

NSGradient(starting: TOP_COLOR, ending: BOTTOM_COLOR)!.draw(in: NSRect(origin: .zero, size: WINDOW), angle: -90)

let title = NSAttributedString(string: TITLE, attributes: [
    .font: NSFont.systemFont(ofSize: TITLE_SIZE, weight: .medium),
    .foregroundColor: TEXT_COLOR,
])
title.draw(at: NSPoint(x: (WINDOW.width - title.size().width) / 2, y: WINDOW.height - TITLE_FROM_TOP - title.size().height / 2))

// A gentle arc from the app to Applications, ending in an arrowhead.
let start = NSPoint(x: APP_X + ICON_HALF + ARROW_GAP, y: iconY)
let end = NSPoint(x: APPLICATIONS_X - ICON_HALF - ARROW_GAP, y: iconY)
let control = NSPoint(x: (start.x + end.x) / 2, y: iconY + ARROW_BEND)
let shaft = NSBezierPath()
shaft.move(to: start)
shaft.curve(to: NSPoint(x: end.x - ARROW_HEAD / 2, y: end.y), controlPoint1: control, controlPoint2: control)
let head = NSBezierPath()
head.move(to: NSPoint(x: end.x - ARROW_HEAD, y: end.y + ARROW_HEAD * 0.8))
head.line(to: end)
head.line(to: NSPoint(x: end.x - ARROW_HEAD, y: end.y - ARROW_HEAD * 0.8))

// The arrow's strokes become a mask that the gradient fills, purple at the app and pink at Applications.
let context = NSGraphicsContext.current!.cgContext
context.saveGState()
context.setLineWidth(ARROW_WIDTH)
context.setLineCap(.round)
context.setLineJoin(.round)
for path in [shaft, head] {
    context.addPath(path.cgPath)
}
context.replacePathWithStrokedPath()
context.clip()
NSGradient(starting: PURPLE, ending: PINK)!.draw(from: NSPoint(x: start.x, y: 0), to: NSPoint(x: end.x, y: 0), options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation])
context.restoreGState()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
