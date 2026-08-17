import AppKit
import CurtainCore

/// Moves another app's status icon across the line, by synthesizing the Cmd-drag
/// a user would perform by hand.
///
/// This is the one place Curtain writes something it does not own, and it is
/// deliberately rare: setup only, never continuous. Ice's habit of re-asserting
/// positions constantly is what stranded an icon in the notch in the first place.
///
/// Every drag is read back. A drag that did not land is reported by name rather
/// than assumed — the missing feedback loop being precisely what made Ice's
/// failure silent.
enum Arranger {
    enum Failure: Error {
        /// The icon is off-screen, so no cursor can reach it.
        case unreachable(name: String)
        /// The drag ran but the icon is not where it was asked to go.
        case didNotLand(name: String, at: CGFloat)
    }

    /// Vertical centre of the menu bar in the top-left space `CGEvent` uses.
    /// AX reports item frames in the same space, so its numbers feed straight in.
    private static let menuBarY: CGFloat = 14

    /// Drag `item` to `targetX`, then confirm.
    static func move(
        _ item: MenuBarItem,
        toX targetX: CGFloat,
        in geometry: MenuBarGeometry
    ) -> Result<ItemFrame, Failure> {
        guard item.frame.minX > 0 else { return .failure(.unreachable(name: item.name)) }

        drag(fromX: item.frame.minX + item.frame.width / 2, toX: targetX)
        // Give the bar a moment to settle before believing anything.
        Thread.sleep(forTimeInterval: 0.5)

        guard let landed = AXMenuBar.items().first(where: { $0.pid == item.pid })?.frame else {
            return .failure(.didNotLand(name: item.name, at: item.frame.minX))
        }
        // Landing within a slot's width of the target is success; the bar snaps
        // items to positions, so exactness is neither offered nor needed.
        guard abs(landed.minX - targetX) < 60 else {
            return .failure(.didNotLand(name: item.name, at: landed.minX))
        }
        return .success(landed)
    }

    private static func drag(fromX: CGFloat, toX: CGFloat, steps: Int = 24) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        // Keep the user's real mouse from fighting the synthetic drag.
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        func post(_ type: CGEventType, _ x: CGFloat) {
            guard let event = CGEvent(
                mouseEventSource: source,
                mouseType: type,
                mouseCursorPosition: CGPoint(x: x, y: menuBarY),
                mouseButton: .left
            ) else { return }
            event.flags = .maskCommand
            event.post(tap: .cghidEventTap)
        }

        post(.mouseMoved, fromX)
        usleep(120_000)
        post(.leftMouseDown, fromX)
        usleep(120_000)
        for step in 1...steps {
            let progress = CGFloat(step) / CGFloat(steps)
            post(.leftMouseDragged, fromX + (toX - fromX) * progress)
            usleep(18_000)
        }
        usleep(120_000)
        post(.leftMouseUp, toX)
    }
}
