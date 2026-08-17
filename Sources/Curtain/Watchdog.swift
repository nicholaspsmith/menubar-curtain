import AppKit
import CurtainCore

/// Names icons that have a slot but nowhere useful to be.
///
/// This exists because of 2026-08-16: KeyLight's icon "disappeared" while the app
/// was perfectly healthy — it had simply been placed at x=837, in the sliver
/// beside the notch, where macOS gives an item a slot and draws nothing. Ice put
/// it there and never checked. Nothing tells the user; the icon is just gone.
///
/// Curtain cannot always fix that (an item right of the line is beyond our
/// reach), but it can always *say so*, and being told is the entire difference.
enum Watchdog {
    /// Items sitting where the user can neither see nor click them.
    ///
    /// Only items to the right of our own line count. Everything left of it is
    /// the block we hid on purpose — reporting that would be reporting our own
    /// work back as a fault, and during a reveal the block legitimately rests
    /// behind the notch on its way in and out.
    static func stranded(in geometry: MenuBarGeometry, ownPID: pid_t) -> [MenuBarItem] {
        let all = AXMenuBar.items()
        let boundary = all.filter { $0.pid == ownPID }.map(\.frame.maxX).max() ?? geometry.usableMinX

        var seen = Set<String>()
        return all
            .filter { $0.pid != ownPID }
            .filter { $0.frame.minX >= boundary }
            .filter { CurtainGeometry.placement(of: $0.frame, in: geometry) == .deadZone }
            // One warning per app: several items from one app say nothing extra.
            .filter { seen.insert($0.name).inserted }
    }
}
