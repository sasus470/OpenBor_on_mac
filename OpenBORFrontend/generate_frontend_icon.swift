import AppKit
import Foundation

guard CommandLine.arguments.count > 1 else {
    fputs("usage: generate_frontend_icon.swift <output-png>\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let size = NSSize(width: 1024, height: 1024)
let canvas = NSImage(size: size)

func roundedRect(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

canvas.lockFocus()

let fullRect = NSRect(origin: .zero, size: size)
let bgGradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.14, green: 0.07, blue: 0.10, alpha: 1),
    NSColor(calibratedRed: 0.33, green: 0.14, blue: 0.12, alpha: 1),
    NSColor(calibratedRed: 0.85, green: 0.40, blue: 0.16, alpha: 1)
])!
bgGradient.draw(in: roundedRect(fullRect.insetBy(dx: 24, dy: 24), radius: 220), angle: -42)

NSColor.black.withAlphaComponent(0.16).setFill()
roundedRect(NSRect(x: 118, y: 116, width: 788, height: 788), radius: 340).fill()

let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowBlurRadius = 30
shadow.shadowOffset = NSSize(width: 0, height: -20)
shadow.set()

let dragonGradient = NSGradient(colors: [
    NSColor(calibratedRed: 1.0, green: 0.84, blue: 0.47, alpha: 1),
    NSColor(calibratedRed: 1.0, green: 0.56, blue: 0.24, alpha: 1),
    NSColor(calibratedRed: 0.84, green: 0.29, blue: 0.13, alpha: 1)
])!

let dragon = NSBezierPath()
dragon.move(to: NSPoint(x: 292, y: 640))
dragon.curve(to: NSPoint(x: 388, y: 754), controlPoint1: NSPoint(x: 276, y: 722), controlPoint2: NSPoint(x: 326, y: 772))
dragon.curve(to: NSPoint(x: 514, y: 764), controlPoint1: NSPoint(x: 430, y: 744), controlPoint2: NSPoint(x: 474, y: 782))
dragon.curve(to: NSPoint(x: 660, y: 704), controlPoint1: NSPoint(x: 588, y: 748), controlPoint2: NSPoint(x: 636, y: 728))
dragon.curve(to: NSPoint(x: 710, y: 568), controlPoint1: NSPoint(x: 706, y: 666), controlPoint2: NSPoint(x: 730, y: 620))
dragon.curve(to: NSPoint(x: 634, y: 428), controlPoint1: NSPoint(x: 694, y: 498), controlPoint2: NSPoint(x: 662, y: 454))
dragon.curve(to: NSPoint(x: 504, y: 392), controlPoint1: NSPoint(x: 594, y: 398), controlPoint2: NSPoint(x: 546, y: 382))
dragon.curve(to: NSPoint(x: 396, y: 420), controlPoint1: NSPoint(x: 456, y: 404), controlPoint2: NSPoint(x: 420, y: 410))
dragon.curve(to: NSPoint(x: 310, y: 536), controlPoint1: NSPoint(x: 344, y: 438), controlPoint2: NSPoint(x: 302, y: 476))
dragon.curve(to: NSPoint(x: 292, y: 640), controlPoint1: NSPoint(x: 314, y: 578), controlPoint2: NSPoint(x: 286, y: 610))
dragon.close()
dragonGradient.draw(in: dragon, angle: -50)

NSColor.white.withAlphaComponent(0.22).setFill()
let crest = NSBezierPath()
crest.move(to: NSPoint(x: 374, y: 690))
crest.curve(to: NSPoint(x: 480, y: 740), controlPoint1: NSPoint(x: 404, y: 742), controlPoint2: NSPoint(x: 450, y: 758))
crest.curve(to: NSPoint(x: 598, y: 714), controlPoint1: NSPoint(x: 540, y: 728), controlPoint2: NSPoint(x: 578, y: 726))
crest.curve(to: NSPoint(x: 534, y: 640), controlPoint1: NSPoint(x: 566, y: 684), controlPoint2: NSPoint(x: 544, y: 660))
crest.curve(to: NSPoint(x: 426, y: 632), controlPoint1: NSPoint(x: 500, y: 630), controlPoint2: NSPoint(x: 460, y: 626))
crest.curve(to: NSPoint(x: 374, y: 690), controlPoint1: NSPoint(x: 394, y: 640), controlPoint2: NSPoint(x: 376, y: 660))
crest.close()
crest.fill()

NSColor(calibratedRed: 0.19, green: 0.10, blue: 0.11, alpha: 0.86).setFill()
let snout = roundedRect(NSRect(x: 468, y: 484, width: 130, height: 120), radius: 46)
snout.fill()

NSColor.white.setFill()
roundedRect(NSRect(x: 484, y: 510, width: 54, height: 42), radius: 20).fill()
roundedRect(NSRect(x: 528, y: 510, width: 54, height: 42), radius: 20).fill()

NSColor(calibratedRed: 0.17, green: 0.10, blue: 0.12, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 505, y: 519, width: 14, height: 18)).fill()
NSBezierPath(ovalIn: NSRect(x: 549, y: 519, width: 14, height: 18)).fill()

let smile = NSBezierPath()
smile.move(to: NSPoint(x: 500, y: 490))
smile.curve(to: NSPoint(x: 566, y: 490), controlPoint1: NSPoint(x: 516, y: 474), controlPoint2: NSPoint(x: 550, y: 474))
NSColor(calibratedRed: 0.34, green: 0.09, blue: 0.07, alpha: 0.9).setStroke()
smile.lineWidth = 8
smile.stroke()

NSColor.white.withAlphaComponent(0.92).setFill()
let fangLeft = NSBezierPath()
fangLeft.move(to: NSPoint(x: 510, y: 486))
fangLeft.line(to: NSPoint(x: 524, y: 486))
fangLeft.line(to: NSPoint(x: 517, y: 462))
fangLeft.close()
fangLeft.fill()

let fangRight = NSBezierPath()
fangRight.move(to: NSPoint(x: 542, y: 486))
fangRight.line(to: NSPoint(x: 556, y: 486))
fangRight.line(to: NSPoint(x: 549, y: 462))
fangRight.close()
fangRight.fill()

NSColor(calibratedRed: 0.16, green: 0.13, blue: 0.15, alpha: 0.94).setFill()
roundedRect(NSRect(x: 272, y: 238, width: 470, height: 238), radius: 110).fill()

let stickGradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.75, green: 0.96, blue: 1.0, alpha: 1),
    NSColor(calibratedRed: 0.31, green: 0.78, blue: 0.95, alpha: 1)
])!
stickGradient.draw(in: NSBezierPath(ovalIn: NSRect(x: 334, y: 280, width: 106, height: 106)), angle: 90)
stickGradient.draw(in: roundedRect(NSRect(x: 379, y: 332, width: 22, height: 88), radius: 11), angle: 90)

let buttonColors: [(NSRect, NSColor)] = [
    (NSRect(x: 564, y: 316, width: 46, height: 46), NSColor(calibratedRed: 1.0, green: 0.45, blue: 0.30, alpha: 1)),
    (NSRect(x: 620, y: 276, width: 42, height: 42), NSColor(calibratedRed: 0.49, green: 0.91, blue: 1.0, alpha: 1)),
    (NSRect(x: 674, y: 318, width: 46, height: 46), NSColor(calibratedRed: 1.0, green: 0.82, blue: 0.33, alpha: 1)),
    (NSRect(x: 620, y: 372, width: 42, height: 42), NSColor(calibratedRed: 0.49, green: 1.0, blue: 0.67, alpha: 1))
]
for (rect, color) in buttonColors {
    color.setFill()
    NSBezierPath(ovalIn: rect).fill()
}

canvas.unlockFocus()

guard let tiff = canvas.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("failed to create icon image\n", stderr)
    exit(1)
}

do {
    try png.write(to: outputURL, options: .atomic)
} catch {
    fputs("failed to write icon image: \(error)\n", stderr)
    exit(1)
}
