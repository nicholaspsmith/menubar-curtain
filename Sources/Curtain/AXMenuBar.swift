import AppKit
import ApplicationServices
import CurtainCore

/// One app's status item, as the accessibility API sees it.
struct MenuBarItem {
    let name: String
    let bundleID: String?
    let pid: pid_t
    let frame: ItemFrame

    /// Stable across relaunches, unlike a pid — what remembered placements are
    /// filed under. Falls back to the name for apps with no bundle identifier.
    var key: String { bundleID ?? name }
}

/// Reads every app's status item position through the accessibility API.
///
/// AX is the only public way to learn where a status item really is. An app's
/// own `NSWindow` frame is a proxy that disagrees with the truth by hundreds of
/// points, and `CGWindowListCopyWindowInfo` attributes every item to Control
/// Center, which hosts them — so it gives geometry without identity. AX gives
/// both, and it reads items parked off-screen just as happily as visible ones.
///
/// Not everything is legible this way: apps that expose no AX status item —
/// Mullvad and Raycast on this machine — simply do not appear. They can still be
/// hidden by the curtain; they just cannot be inspected or arranged for.
enum AXMenuBar {
    /// Apps can wedge; never block the menu waiting on one.
    private static let messagingTimeout: Float = 0.4

    static var isTrusted: Bool { AXIsProcessTrusted() }

    @discardableResult
    static func requestTrust() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    static func items() -> [MenuBarItem] {
        guard isTrusted else { return [] }
        var found: [MenuBarItem] = []
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy != .prohibited, !app.isTerminated else { continue }
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, messagingTimeout)
            guard let bar = statusItemBar(of: element) else { continue }
            for child in children(of: bar) {
                guard let frame = frame(of: child) else { continue }
                found.append(MenuBarItem(
                    name: app.localizedName ?? "Unknown",
                    bundleID: app.bundleIdentifier,
                    pid: app.processIdentifier,
                    frame: frame
                ))
            }
        }
        return found
    }

    // MARK: - AX plumbing

    /// The bar holding status items — `AXExtrasMenuBar`, and only that.
    ///
    /// Falling back to `AXMenuBar` looks tempting for accessory apps but is
    /// wrong: for a regular app that attribute is the *app menu* (Apple, File,
    /// Edit, View, Window…), whose items all sit at the left of the screen and
    /// therefore read as stranded. It flooded the menu with a warning per menu
    /// title per app.
    private static func statusItemBar(of app: AXUIElement) -> AXUIElement? {
        copyElement(app, "AXExtrasMenuBar")
    }

    private static func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement]
        else { return [] }
        return children
    }

    private static func frame(of element: AXUIElement) -> ItemFrame? {
        guard let position: CGPoint = axValue(element, kAXPositionAttribute, .cgPoint),
              let size: CGSize = axValue(element, kAXSizeAttribute, .cgSize),
              size.width > 0
        else { return nil }
        return ItemFrame(minX: position.x, width: size.width)
    }

    private static func axValue<T>(_ element: AXUIElement, _ attribute: String, _ type: AXValueType) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        let result = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { result.deallocate() }
        guard AXValueGetValue(value as! AXValue, type, result) else { return nil }
        return result.pointee
    }
}
