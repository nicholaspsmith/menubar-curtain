import AppKit
import CurtainCore
import StatusItemKit

/// The curtain: a single status item that is both the hiding mechanism and the
/// control you click.
///
/// Its *width* is the entire hide/show state. A status item grows leftward — the
/// right edge stays put, and neighbours to the right never move (measured on
/// macOS 26) — so a wide item slides the block to its left clean off the display
/// while disturbing nothing else. No other app's state is ever written, which is
/// why this cannot strand an icon the way Ice does.
///
/// Line and handle are deliberately the *same* item rather than two. A packed
/// menu bar has no free slot: when they were separate, the handle was the item
/// that got bumped off-screen, leaving no way to unhide. Merging them means the
/// control lives at the item's right edge, which is always in the visible
/// region, however wide the item grows.
final class CurtainItem {
    private let controller: StatusItemController

    /// Width when shown — just the chevron plus the usual padding.
    private static let naturalWidth: CGFloat = 30

    /// How much room to assume the hidden block needs before Task 5 measures it.
    /// Nine icons came to roughly 280pt; 400 leaves slack without wasting bar.
    static let assumedBlockWidth: CGFloat = 400

    init(controller: StatusItemController) {
        self.controller = controller
    }

    /// Right edge in screen points, or nil before the system has placed the item.
    var rightEdge: CGFloat? { controller.button?.window?.frame.maxX }

    var width: CGFloat { controller.length }

    /// Whether the last `hide` could actually be computed. False means the item
    /// is not somewhere we can hide from, and we have deliberately stayed narrow.
    private(set) var isEffective = false

    func hide(blockWidth: CGFloat = assumedBlockWidth, in geometry: MenuBarGeometry) {
        // Until the system places the item its window sits at x=0, and an item
        // whose right edge is left of the usable area cannot hide anything
        // anyway — everything beside it is already lost in the notch.
        //
        // Fail safe: stay narrow and try again on the next poll. Guessing a huge
        // width here is self-defeating, because a far-left item stays far left
        // and simply wedges itself out of the user's reach.
        guard let edge = rightEdge, edge > geometry.usableMinX else {
            isEffective = false
            show()
            return
        }
        isEffective = true
        let width = CurtainGeometry.hideWidth(
            lineRightEdge: edge,
            blockWidth: blockWidth,
            in: geometry
        )
        controller.length = width
        draw(.left)
    }

    func show() {
        controller.length = Self.naturalWidth
        draw(.right)
    }

    /// Render the chevron at the item's right edge.
    ///
    /// A right-aligned attributed title, not an image: an `NSStatusBarButton`
    /// centres its image, and a chevron composited into an 869pt-wide image
    /// rendered nothing at all here. Text alignment is handled by the text
    /// system and works at any button width.
    private func draw(_ direction: Direction) {
        guard let button = controller.button else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        button.image = nil
        button.imagePosition = .noImage
        button.attributedTitle = NSAttributedString(
            string: direction.glyph,
            attributes: [
                .paragraphStyle: paragraph,
                .foregroundColor: NSColor.labelColor,
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            ]
        )
    }

    // MARK: - Drawing

    enum Direction {
        case left, right
        /// Points the way the icons will go when clicked.
        var glyph: String { self == .left ? "❮" : "❯" }
        var label: String { self == .left ? "Icons hidden" : "Icons shown" }
    }

    /// A chevron pinned to the right edge of an image as wide as the item.
    ///
    /// An `NSStatusBarButton` centres its image, so a normal-sized glyph in a
    /// 900pt-wide item would render 400pt off the left of the display. Drawing
    /// into a full-width image puts the chevron where the user can see and click
    /// it — at the item's right edge, which is always in the visible region.
    ///
    /// Stroked as a path rather than composited from an SF Symbol: drawing one
    /// `NSImage` inside another's handler rendered nothing here, and paths are
    /// what `MeterIcon` uses across these apps anyway.
    private static func chevron(_ direction: Direction, spanning width: CGFloat) -> NSImage {
        let height: CGFloat = 18
        let arm: CGFloat = 5      // horizontal reach of each stroke
        let rise: CGFloat = 4.5   // vertical reach of each stroke
        let drawn = max(width - 12, arm + 4)

        let image = NSImage(size: NSSize(width: drawn, height: height), flipped: false) { rect in
            let right = rect.maxX - 2
            let left = right - arm
            let midY = rect.midY
            let path = NSBezierPath()
            switch direction {
            case .left:
                path.move(to: NSPoint(x: right, y: midY + rise))
                path.line(to: NSPoint(x: left, y: midY))
                path.line(to: NSPoint(x: right, y: midY - rise))
            case .right:
                path.move(to: NSPoint(x: left, y: midY + rise))
                path.line(to: NSPoint(x: right, y: midY))
                path.line(to: NSPoint(x: left, y: midY - rise))
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
