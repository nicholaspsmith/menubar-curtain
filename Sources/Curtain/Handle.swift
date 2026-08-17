import AppKit
import StatusItemKit

/// The visible control: a narrow status item showing which way the curtain is
/// drawn, carrying the menu.
///
/// Narrow on purpose. A status item only renders when its slot fits entirely
/// within the usable area, so the control has to be small enough to sit beside
/// the user's own icons — which is exactly why it cannot also be the curtain.
final class Handle {
    private let controller: StatusItemController

    init(controller: StatusItemController) {
        self.controller = controller
    }

    func draw(hidden: Bool) {
        controller.setIcon(Self.chevron(pointingLeft: hidden))
    }

    /// A chevron stroked as a path, matching how `MeterIcon` draws across these
    /// apps. Points the way the icons will go when clicked.
    private static func chevron(pointingLeft: Bool) -> NSImage {
        let side: CGFloat = 18
        let arm: CGFloat = 4.5
        let rise: CGFloat = 4.5

        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let midX = rect.midX
            let midY = rect.midY
            let path = NSBezierPath()
            if pointingLeft {
                path.move(to: NSPoint(x: midX + arm / 2, y: midY + rise))
                path.line(to: NSPoint(x: midX - arm / 2, y: midY))
                path.line(to: NSPoint(x: midX + arm / 2, y: midY - rise))
            } else {
                path.move(to: NSPoint(x: midX - arm / 2, y: midY + rise))
                path.line(to: NSPoint(x: midX + arm / 2, y: midY))
                path.line(to: NSPoint(x: midX - arm / 2, y: midY - rise))
            }
            path.lineWidth = 1.8
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            // Template tinting keys off alpha, so the ink colour is irrelevant.
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
