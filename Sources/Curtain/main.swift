import AppKit
import CurtainCore
import StatusItemKit

/// Curtain — hides a contiguous block of menu-bar icons by widening a status
/// item of its own, never by moving anyone else's.
///
/// See docs/superpowers/specs/2026-08-17-menubar-curtain-design.md for why that
/// distinction is the entire point of the app.
///
/// Two items, because they cannot be one: macOS renders a status item only when
/// its slot fits entirely within the usable area right of the notch, so the
/// curtain — hundreds of points wide — is permanently invisible, and the control
/// has to be a separate narrow item beside the user's own icons.
final class App: NSObject, NSApplicationDelegate {
    private var controller: StatusItemController!
    private var handle: Handle!
    private let line = Line()
    private var isHidden = true
    /// False until the menu bar has had a chance to place our narrow items.
    private var hasSettled = false
    private var rehideTimer: Timer?
    private var revealMode = RevealModeStore.load(from: .standard)
    private var peekToken = UUID().uuidString
    private static let settleDelay: TimeInterval = 1.5
    /// Comfortably longer than the 5s poll that refreshes it, short enough that a
    /// crashed Curtain returns the sibling icons quickly.
    private static let yieldTTL: TimeInterval = 15

    /// Where to park our two items on a bar we have never seen.
    ///
    /// The preferred-position scale is opaque and relative to whatever else is
    /// installed, and larger means further left. The line must rank left of the
    /// icons to keep and right of the icons to hide; the handle ranks just right
    /// of the line so it lands in the visible strip. The user can Cmd-drag either
    /// one, and macOS persists wherever they leave it.
    private static let defaults: [String: Double] = [
        "NSStatusItem Preferred Position CurtainLine": 600,
        "NSStatusItem Preferred Position CurtainHandle": 590,
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Seed positions before the items exist — macOS reads these when an item
        // is created, and never again.
        for (key, value) in Self.defaults where UserDefaults.standard.object(forKey: key) == nil {
            UserDefaults.standard.set(value, forKey: key)
        }

        controller = StatusItemController(
            pollInterval: 5,
            onPoll: { [weak self] in self?.applyState() },
            onBuildMenu: { [weak self] menu in self?.buildMenu(menu) },
            autosaveName: "CurtainHandle",
            onPrimaryClick: { [weak self] in self?.toggle() }
        )
        handle = Handle(controller: controller)
        controller.start()
        settleThenApply()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    // MARK: - Curtain state

    private func applyState() {
        handle.draw(hidden: isHidden)

        // Never widen before the system has placed the line. An item created —
        // or re-placed — while already wide does not fit at its ranked spot, so
        // macOS drops it wherever it will go and shoves every other icon aside;
        // measured, it landed right of everything and hid the lot.
        guard hasSettled else {
            line.show()
            return
        }
        if isHidden {
            line.hide()
        } else {
            // Ask the sibling apps for their slots *before* collapsing, so the
            // block has somewhere to land. Without this a reveal just slides the
            // icons behind the notch — the bar has about 43pt spare and the block
            // needs ten times that.
            //
            // Re-posted on every poll tick rather than once: each client arms a
            // short self-restore timer from the TTL, so a crashed Curtain can
            // never leave their icons hidden. Refreshing it is what holds the
            // reveal open.
            MenuBarYield.post(.init(state: .yield, token: peekToken, ttl: Self.yieldTTL))
            line.show()
        }
    }

    /// Stay narrow, let the menu bar place us, then apply the real state.
    private func settleThenApply() {
        hasSettled = false
        line.show()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay) { [weak self] in
            self?.hasSettled = true
            self?.applyState()
        }
    }

    /// A dock, undock or resolution change re-places every item, so go narrow and
    /// let the bar settle before widening again.
    @objc private func screensChanged() {
        settleThenApply()
    }

    // MARK: - Menu

    private func buildMenu(_ menu: NSMenu) {
        // No show/hide row: the handle itself is the toggle, and a menu entry
        // duplicating a left click is just noise.
        menu.removeAllItems()

        if AXMenuBar.isTrusted {
            let stranded = Watchdog.stranded(
                in: MenuBarGeometry.current(),
                ownPID: ProcessInfo.processInfo.processIdentifier
            )
            for item in stranded {
                menu.addItem(disabledItem("⚠ \(item.name) is in the notch dead zone"))
            }
        } else {
            menu.addItem(actionItem("⚠ Grant Accessibility…", #selector(grantTrust)))
        }

        // Only once something is above it, or the menu opens on a stray line.
        if !menu.items.isEmpty { menu.addItem(.separator()) }

        let reveal = NSMenuItem(title: "When Showing", action: nil, keyEquivalent: "")
        reveal.submenu = buildRevealMenu()
        menu.addItem(reveal)

        let login = actionItem("Start at Login", #selector(toggleLogin))
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(actionItem("Quit Curtain", #selector(quit), key: "q"))
    }

    private func actionItem(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        NSMenuItem(title: title, action: nil, keyEquivalent: "")
    }

    /// Rebuilt on every open, so the checkmark always reflects the live choice.
    private func buildRevealMenu() -> NSMenu {
        let menu = NSMenu()
        for mode in RevealMode.allCases {
            let item = actionItem(mode.label, #selector(selectRevealMode(_:)))
            item.representedObject = mode.rawValue
            item.state = mode == revealMode ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    // MARK: - Menu selectors

    /// Left-clicking the handle flips the curtain; the chevron flips with it, so
    /// the icon itself says which way round things are.
    @objc private func toggle() {
        isHidden.toggle()
        if !isHidden { peekToken = UUID().uuidString }

        applyState()
        if isHidden {
            // Widen the line first, then hand the width back — both in the same
            // turn of the run loop, so the icons return together rather than the
            // bar visibly filling in twice.
            //
            // This used to wait 0.6s, back when yielding hid items outright and a
            // sibling restored too early had nowhere to land. Yielding by width
            // keeps every item in place, so there is nothing left to wait for.
            MenuBarYield.post(.init(state: .restore, token: peekToken, ttl: 0))
        }

        rehideTimer?.invalidate()
        rehideTimer = nil
        guard !isHidden, revealMode == .timeout else { return }
        rehideTimer = Timer.scheduledTimer(
            withTimeInterval: RevealModeStore.timeoutDuration,
            repeats: false
        ) { [weak self] _ in
            guard let self, !self.isHidden else { return }
            self.isHidden = true
            self.applyState()
        }
    }

    @objc private func selectRevealMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = RevealMode(rawValue: raw)
        else { return }
        revealMode = mode
        RevealModeStore.save(mode, to: .standard)
        // A mode change must not strand a reveal under the old rules.
        if mode == .toggle {
            rehideTimer?.invalidate()
            rehideTimer = nil
        }
    }

    @objc private func grantTrust() { AXMenuBar.requestTrust() }

    @objc private func toggleLogin() { LoginItem.toggle() }

    @objc private func quit() {
        // Leave the bar as we found it rather than with the block off-screen.
        line.show()
        NSApp.terminate(nil)
    }
}

// MARK: - Entry point

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = App()
app.delegate = delegate
app.run()
