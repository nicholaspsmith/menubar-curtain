import AppKit
import CurtainCore

/// The hidden icons, presented as a menu.
///
/// Deliberately a real `NSMenu` rather than a custom panel: submenus, keyboard
/// navigation, hover, and dismissal all come for free and look like the rest of
/// the system. Each hidden app is a row; its submenu is that app's *actual* menu,
/// read live over the accessibility API, so a hidden app stays usable without any
/// icon moving anywhere.
final class PanelMenu: NSObject, NSMenuDelegate {
    private var pidForMenu: [ObjectIdentifier: pid_t] = [:]

    /// - Parameter manage: the checklist of which icons are hidden, appended so
    ///   it sits where someone looking at the hidden items would reach for it.
    func build(hidden apps: [HiddenApp], manage: NSMenu?) -> NSMenu {
        let menu = NSMenu()
        pidForMenu.removeAll()

        if apps.isEmpty {
            let empty = NSMenuItem(title: "No hidden icons", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }

        for app in apps {
            let item = NSMenuItem(title: app.name, action: nil, keyEquivalent: "")
            if let icon = app.icon {
                icon.size = NSSize(width: 16, height: 16)
                item.image = icon
            }
            if AXMenuDriver.hasMenu(forPID: app.pid) {
                let submenu = NSMenu()
                submenu.delegate = self
                pidForMenu[ObjectIdentifier(submenu)] = app.pid
                item.submenu = submenu
            } else {
                // No menu to present, so press the icon itself — for an app like
                // Bitwarden that press is how it opens. Falling back to revealing
                // the bar was worse than useless: picking the app did something
                // unrelated to the app.
                item.action = #selector(openApp(_:))
                item.target = self
                item.representedObject = RowRef(pid: app.pid, index: -1)
                item.toolTip = "\(app.name) publishes no menu; this opens it directly."
            }
            menu.addItem(item)
        }

        if let manage {
            menu.addItem(.separator())
            let item = NSMenuItem(title: "Manage Icons…", action: nil, keyEquivalent: "")
            item.submenu = manage
            menu.addItem(item)
        }
        return menu
    }

    // MARK: - Lazy submenus

    /// Filled when opened, not when built: reading a menu means asking the owning
    /// app to open it, and doing that for every hidden app on every click would
    /// be both slow and rude.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let pid = pidForMenu[ObjectIdentifier(menu)] else { return }
        menu.removeAllItems()
        for row in AXMenuDriver.rows(forPID: pid) {
            if row.isSeparator {
                menu.addItem(.separator())
                continue
            }
            // A row's own title can be several lines (account details, say);
            // keep the first, which is the part that identifies it.
            let title = row.title.components(separatedBy: .newlines).first ?? row.title
            let item = NSMenuItem(
                title: title,
                action: #selector(pressRow(_:)),
                keyEquivalent: row.keyEquivalent
            )
            item.keyEquivalentModifierMask = row.modifiers
            item.target = self
            item.representedObject = RowRef(pid: pid, index: row.index)
            item.isEnabled = row.isEnabled
            menu.addItem(item)
        }
        if menu.items.isEmpty {
            let empty = NSMenuItem(title: "No menu", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
    }

    // MARK: - Actions

    private final class RowRef: NSObject {
        let pid: pid_t
        let index: Int
        init(pid: pid_t, index: Int) {
            self.pid = pid
            self.index = index
        }
    }

    /// Driving another app's menu has to wait until ours has finished closing.
    /// Pressed inline, the action is swallowed — measured against Tailscale,
    /// where the identical press works standalone and does nothing from here.
    private func afterMenuCloses(_ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    @objc private func pressRow(_ sender: NSMenuItem) {
        guard let ref = sender.representedObject as? RowRef else { return }
        afterMenuCloses { AXMenuDriver.press(rowIndex: ref.index, forPID: ref.pid) }
    }

    @objc private func openApp(_ sender: NSMenuItem) {
        guard let ref = sender.representedObject as? RowRef else { return }
        afterMenuCloses { AXMenuDriver.pressItem(forPID: ref.pid) }
    }
}
