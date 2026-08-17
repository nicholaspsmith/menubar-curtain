import AppKit
import ApplicationServices

/// One row of another app's status-item menu.
struct AXMenuRow {
    let index: Int
    let title: String
    let isEnabled: Bool
    var isSeparator: Bool { title.isEmpty }
}

/// Reads and drives another app's status-item menu through the accessibility
/// API, while that item is parked off-screen.
///
/// This is what makes hiding an icon survivable. An off-screen item can still be
/// *activated* — but its menu then draws off-screen too (measured at x=-4355),
/// so pressing it is useless on its own. Reading the menu instead and presenting
/// the rows ourselves means a hidden app stays fully usable without moving a
/// single icon. Verified end to end: rows read by name, a chosen row pressed,
/// and the target app's handler fired.
///
/// Needs only the Accessibility grant Curtain already holds — no Automation
/// permission, because nothing goes through System Events.
enum AXMenuDriver {
    private static let timeout: Float = 1.0

    /// The rows of an app's first status-item menu, in order.
    static func rows(forPID pid: pid_t) -> [AXMenuRow] {
        guard let menu = menu(forPID: pid, allowPress: true) else { return [] }
        defer { close(menu) }
        return children(of: menu).enumerated().map { index, element in
            AXMenuRow(
                index: index,
                title: string(element, kAXTitleAttribute) ?? "",
                isEnabled: bool(element, kAXEnabledAttribute) ?? true
            )
        }
    }

    /// True when the app exposes a menu we can present. Mullvad and Raycast do
    /// not, and fall back to being revealed in the bar instead.
    ///
    /// Never presses the item. For an app whose icon opens a window rather than a
    /// menu, pressing *is* the action — probing Bitwarden this way threw its
    /// window open just from building the panel. An app that only constructs its
    /// menu on press therefore shows no submenu here, which is the right trade:
    /// merely listing what is hidden must not set anything off.
    static func hasMenu(forPID pid: pid_t) -> Bool {
        guard let menu = menu(forPID: pid, allowPress: false) else { return false }
        defer { close(menu) }
        return !children(of: menu).isEmpty
    }

    /// Activate a row by index. Index rather than title: several rows can share a
    /// title, and separators have none at all.
    @discardableResult
    static func press(rowIndex: Int, forPID pid: pid_t) -> Bool {
        guard let menu = menu(forPID: pid, allowPress: true) else { return false }
        let rows = children(of: menu)
        guard rows.indices.contains(rowIndex) else {
            close(menu)
            return false
        }
        // Do not cancel this menu: pressing the row is what dismisses it, and
        // cancelling first would throw away the action.
        return AXUIElementPerformAction(rows[rowIndex], kAXPressAction as CFString) == .success
    }

    // MARK: - AX plumbing

    /// - Parameter allowPress: whether we may press the status item to make its
    ///   menu appear. Only safe once the user has asked for that app's menu —
    ///   pressing an item that opens a window instead of a menu launches it.
    private static func menu(forPID pid: pid_t, allowPress: Bool) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, timeout)
        guard let bar = element(app, "AXExtrasMenuBar"),
              let item = children(of: bar).first
        else { return nil }

        if let menu = children(of: item).first { return menu }
        guard allowPress else { return nil }
        // Some apps only build the menu once the item is pressed.
        AXUIElementPerformAction(item, kAXPressAction as CFString)
        return children(of: item).first
    }

    private static func close(_ menu: AXUIElement) {
        AXUIElementPerformAction(menu, kAXCancelAction as CFString)
    }

    private static func element(_ e: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    private static func children(of e: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &value) == .success,
              let kids = value as? [AXUIElement]
        else { return [] }
        return kids
    }

    private static func string(_ e: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func bool(_ e: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attribute as CFString, &value) == .success else { return nil }
        return value as? Bool
    }
}
