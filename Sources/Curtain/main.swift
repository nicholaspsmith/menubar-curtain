import AppKit
import CurtainCore
import StatusItemKit

/// Curtain — hides a contiguous block of menu-bar icons by widening a status
/// item of its own, never by moving anyone else's.
///
/// See docs/superpowers/specs/2026-08-17-menubar-curtain-design.md for why that
/// distinction is the entire point of the app.
final class App: NSObject, NSApplicationDelegate {
    private var handle: StatusItemController!
    private var curtain: CurtainItem!
    private var isHidden = true
    /// False until the menu bar has had a chance to place our narrow item.
    private var hasSettled = false
    private static let settleDelay: TimeInterval = 1.5

    /// Where to park the curtain on a bar we have never seen.
    ///
    /// The preferred-position scale is opaque and relative to whatever else is
    /// installed; 600 sits just left of this machine's leftmost third-party icon,
    /// which is the right neighbourhood. The user can Cmd-drag it anywhere, and
    /// macOS persists wherever they leave it.
    private static let defaultPosition: Double = 600
    private static let positionKey = "NSStatusItem Preferred Position Curtain"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Seed the position before the item exists — macOS reads this when the
        // item is created, and never again.
        if UserDefaults.standard.object(forKey: Self.positionKey) == nil {
            UserDefaults.standard.set(Self.defaultPosition, forKey: Self.positionKey)
        }

        handle = StatusItemController(
            pollInterval: 5,
            // Re-apply rather than merely redraw: the line's width depends on
            // where the system placed it, which is not known at launch and can
            // change when another app appears or a display is reconfigured.
            onPoll: { [weak self] in self?.applyState() },
            onBuildMenu: { [weak self] menu in self?.buildMenu(menu) },
            autosaveName: "Curtain"
        )
        curtain = CurtainItem(controller: handle)
        handle.start()
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
        // Never grow before the system has placed the item. A status item that is
        // created — or re-placed — while already wide does not fit at its ranked
        // spot, so macOS drops it wherever it will go and shoves every other icon
        // aside; measured, it landed right of everything and hid the lot. Placed
        // narrow first, it takes its ranked spot and then grows leftward with its
        // right edge pinned, which is the behaviour the whole design rests on.
        guard hasSettled else {
            curtain.show()
            return
        }
        let geometry = MenuBarGeometry.current()
        if isHidden {
            curtain.hide(in: geometry)
        } else {
            curtain.show()
        }
    }

    /// Show narrow, let the menu bar place us, then apply the real state.
    private func settleThenApply() {
        hasSettled = false
        curtain.show()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay) { [weak self] in
            self?.hasSettled = true
            self?.applyState()
        }
    }

    /// A dock, undock or resolution change moves the notch boundary and every
    /// item with it, so the line's width has to be recomputed from scratch.
    @objc private func screensChanged() {
        // Placement is decided afresh on a display change, so go narrow and let
        // the bar settle before growing again.
        settleThenApply()
    }

    // MARK: - Menu

    private func buildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(actionItem(isHidden ? "Show Icons" : "Hide Icons", #selector(toggle)))
        menu.addItem(.separator())

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

    // MARK: - Menu selectors

    @objc private func toggle() {
        isHidden.toggle()
        applyState()
    }

    @objc private func toggleLogin() { LoginItem.toggle() }

    @objc private func quit() {
        // Leave the bar as we found it rather than with the block off-screen.
        curtain.show()
        NSApp.terminate(nil)
    }
}

// MARK: - Entry point

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = App()
app.delegate = delegate
app.run()
