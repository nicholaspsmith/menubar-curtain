// Draws Curtain's app icon and writes a 1024pt master PNG.
//
// The picture is the mechanism: icons sliding leftward off the edge, fading as
// they go, with the chevron you click standing at the boundary.
//
// Run via scripts/make-icon.sh, which builds the .icns from this.
import AppKit

let side: CGFloat = 1024
let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
    let rect = NSRect(x: 0, y: 0, width: side, height: side)

    // Squircle-ish background, near-black with a cool cast so it reads on both
    // light and dark desktops.
    let radius = side * 0.2237
    let background = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    background.addClip()
    NSGradient(
        colors: [
            NSColor(calibratedRed: 0.20, green: 0.22, blue: 0.26, alpha: 1),
            NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.11, alpha: 1),
        ]
    )?.draw(in: rect, angle: -90)

    // The menu bar strip the icons live on.
    let strip = NSRect(x: 0, y: side * 0.42, width: side, height: side * 0.16)
    NSColor(white: 1, alpha: 0.06).setFill()
    strip.fill()

    // Icons sliding away to the left, fading as they cross the line.
    let dotY = strip.midY
    let dotRadius = side * 0.045
    for (index, alpha) in [0.95, 0.55, 0.22].enumerated() {
        let x = side * 0.44 - CGFloat(index) * side * 0.135
        let dot = NSBezierPath(ovalIn: NSRect(
            x: x - dotRadius,
            y: dotY - dotRadius,
            width: dotRadius * 2,
            height: dotRadius * 2
        ))
        NSColor(white: 1, alpha: alpha).setFill()
        dot.fill()
    }

    // The curtain itself: the edge everything disappears behind.
    let edgeX = side * 0.56
    NSColor(white: 1, alpha: 0.18).setStroke()
    let edge = NSBezierPath()
    edge.move(to: NSPoint(x: edgeX, y: side * 0.30))
    edge.line(to: NSPoint(x: edgeX, y: side * 0.70))
    edge.lineWidth = side * 0.012
    edge.lineCapStyle = .round
    edge.stroke()

    // The chevron you click.
    let chevron = NSBezierPath()
    let armX = side * 0.105
    let armY = side * 0.105
    let tipX = side * 0.68
    chevron.move(to: NSPoint(x: tipX + armX, y: dotY + armY))
    chevron.line(to: NSPoint(x: tipX, y: dotY))
    chevron.line(to: NSPoint(x: tipX + armX, y: dotY - armY))
    chevron.lineWidth = side * 0.052
    chevron.lineCapStyle = .round
    chevron.lineJoinStyle = .round
    NSColor.white.setStroke()
    chevron.stroke()

    return true
}

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:])
else {
    FileHandle.standardError.write(Data("could not render icon\n".utf8))
    exit(1)
}

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-master.png"
try png.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
