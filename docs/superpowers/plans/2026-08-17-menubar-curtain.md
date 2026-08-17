# Menu Bar Curtain Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `Curtain.app`, a menu-bar manager that hides a contiguous block of third-party icons and cannot strand an icon, replacing Ice.

**Architecture:** A `line` status item whose *width* is the entire hide/show state (wide = hidden, ~1 = shown), plus a clickable `handle`. Nothing another app owns is written during normal operation; positions are only touched once, at setup, and always read back to verify. Peek frees space by asking our own apps to hide themselves over `DistributedNotificationCenter`.

**Tech Stack:** Swift 5.9, SwiftPM, AppKit, XCTest, StatusItemKit (app shell, bundling, login item), HotkeyKit (optional global hotkey), Accessibility APIs for reading and dragging other apps' items.

**Spec:** `docs/superpowers/specs/2026-08-17-menubar-curtain-design.md`

## Global Constraints

- Swift tools version `5.9`; platform floor `.macOS(.v13)`; `LSMinimumSystemVersion` `13.0`.
- Bundle identifier `com.nicholaspsmith.Curtain`; product name `Curtain`; `LSUIElement` true.
- Tests are XCTest (`final class XTests: XCTestCase`), matching `Tests/KeyLightCoreTests`.
- Local package deps by path: `../StatusItemKit`, `../HotkeyKit`.
- Build via `scripts/build-app.sh` → `../StatusItemKit/scripts/make-app.sh Curtain "Curtain"`; never hand-roll signing.
- All geometry logic lives in `CurtainCore` with no AppKit import, so it is unit-testable.
- Measured constants that must appear verbatim: max effective status item width `5000`; dead-zone margin default `40` (empirical: x=837 did not render, x=871 did, usable area starts at x=828).
- Yield notification name `com.nicholaspsmith.menubar.yield`.

---

### Task 0: Prove the synthesized Cmd-drag (Phase 0 gate)

Nothing downstream matters if we cannot move another app's item. This is a probe, not shipped code, but its finding is recorded in the repo.

**Files:**
- Create: `scripts/drag-probe.swift`
- Modify: `docs/superpowers/specs/2026-08-17-menubar-curtain-design.md` (record the finding)

- [ ] **Step 1: Write the probe** — a fixture status-item app plus a drag routine: `CGEventCreateMouseEvent` for `.leftMouseDown` with `.maskCommand` at the item's centre, several `.leftMouseDragged` steps toward the target x, then `.leftMouseUp`, wrapped in `CGEventSource(stateID: .hidSystemState)` with `setLocalEventsFilterDuringSuppressionState(.permitAllEvents, state: .eventSuppressionStateSuppressionInterval)`.
- [ ] **Step 2: Run it against the fixture** with Ice quit, and read the resulting frame back via AX.
- [ ] **Step 3: Record the outcome in the spec** under a new "Phase 0 result" heading — whether the drag landed, how many pixels off, and whether the position persisted to the app's defaults.
- [ ] **Step 4: Commit** `git commit -m "spike: verify synthesized cmd-drag moves a status item"`

**Gate:** if the drag is unreliable, Task 7 changes to a display-only list plus hand-arranging, and the spec's "Known limitations" grows accordingly. Do not proceed to Task 7 without this result.

---

### Task 1: CurtainCore geometry

**Files:**
- Create: `Sources/CurtainCore/Geometry.swift`
- Create: `Tests/CurtainCoreTests/GeometryTests.swift`
- Create: `Package.swift`

**Interfaces:**
- Produces: `MenuBarGeometry(usableMinX:usableMaxX:deadZoneMargin:)`, `ItemFrame(minX:width:)` with `.maxX`, `Placement.{visible,deadZone,hidden}`, `CurtainGeometry.placement(of:in:)`, `CurtainGeometry.hideWidth(lineRightEdge:blockWidth:in:)`, `CurtainGeometry.showWidth`, `CurtainGeometry.maxLineWidth`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import CurtainCore

final class GeometryTests: XCTestCase {
    // The real built-in display, measured 2026-08-16.
    private let screen = MenuBarGeometry(usableMinX: 828, usableMaxX: 1496)

    func testItemInTheNotchSliverIsDeadZone() {
        // KeyLight's actual stranded frame: on paper inside the usable area,
        // in practice invisible.
        let stranded = ItemFrame(minX: 837, width: 32)
        XCTAssertEqual(CurtainGeometry.placement(of: stranded, in: screen), .deadZone)
    }

    func testItemClearOfTheSliverIsVisible() {
        // Where repositioning in Ice put it, and where it rendered fine.
        XCTAssertEqual(CurtainGeometry.placement(of: ItemFrame(minX: 919, width: 32), in: screen), .visible)
    }

    func testItemPushedOffTheLeftEdgeIsHidden() {
        XCTAssertEqual(CurtainGeometry.placement(of: ItemFrame(minX: -4253, width: 24), in: screen), .hidden)
    }

    func testHideWidthPushesWholeBlockPastUsableEdge() {
        let width = CurtainGeometry.hideWidth(lineRightEdge: 871, blockWidth: 280, in: screen)
        // Block's right edge starts at the line's left edge; everything must
        // end up left of usableMinX.
        XCTAssertGreaterThanOrEqual(871 - width, screen.usableMinX - 280)
        XCTAssertLessThanOrEqual(width, CurtainGeometry.maxLineWidth)
    }

    func testHideWidthNeverExceedsTheClamp() {
        let width = CurtainGeometry.hideWidth(lineRightEdge: 1490, blockWidth: 9000, in: screen)
        XCTAssertEqual(width, CurtainGeometry.maxLineWidth)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter GeometryTests`
Expected: FAIL — no such module `CurtainCore`.

- [ ] **Step 3: Write `Package.swift` and the minimal implementation**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Curtain",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Curtain", targets: ["Curtain"]),
        .library(name: "CurtainCore", targets: ["CurtainCore"]),
    ],
    dependencies: [
        .package(path: "../StatusItemKit"),
        .package(path: "../HotkeyKit"),
    ],
    targets: [
        .target(name: "CurtainCore"),
        .executableTarget(
            name: "Curtain",
            dependencies: [
                "CurtainCore",
                .product(name: "StatusItemKit", package: "StatusItemKit"),
                .product(name: "HotkeyKit", package: "HotkeyKit"),
            ]
        ),
        .testTarget(name: "CurtainCoreTests", dependencies: ["CurtainCore"]),
    ]
)
```

```swift
import Foundation

/// The stretch of menu bar a status item may occupy, in screen points.
/// `usableMinX` is `NSScreen.auxiliaryTopRightArea.minX` — the right edge of the
/// notch on a notched display, 0 on a display without one.
public struct MenuBarGeometry: Equatable, Sendable {
    public let usableMinX: CGFloat
    public let usableMaxX: CGFloat
    /// Items whose left edge sits within this many points of `usableMinX` are
    /// unreliable: macOS gives them a slot but draws nothing. Empirical — on the
    /// built-in display an item at x=837 was invisible while one at x=871 drew
    /// normally, with the usable area starting at x=828.
    public let deadZoneMargin: CGFloat

    public init(usableMinX: CGFloat, usableMaxX: CGFloat, deadZoneMargin: CGFloat = 40) {
        self.usableMinX = usableMinX
        self.usableMaxX = usableMaxX
        self.deadZoneMargin = deadZoneMargin
    }
}

public struct ItemFrame: Equatable, Sendable {
    public let minX: CGFloat
    public let width: CGFloat
    public var maxX: CGFloat { minX + width }
    public init(minX: CGFloat, width: CGFloat) {
        self.minX = minX
        self.width = width
    }
}

public enum Placement: Equatable, Sendable {
    case visible
    case deadZone
    case hidden
}

public enum CurtainGeometry {
    /// NSStatusItem lengths clamp near 5012pt in practice; stay just under.
    public static let maxLineWidth: CGFloat = 5000
    /// The line still needs a sliver of width to exist as an item.
    public static let showWidth: CGFloat = 1

    public static func placement(of frame: ItemFrame, in geometry: MenuBarGeometry) -> Placement {
        if frame.maxX <= geometry.usableMinX { return .hidden }
        if frame.minX < geometry.usableMinX + geometry.deadZoneMargin { return .deadZone }
        return .visible
    }

    /// Width the line must take so a block of `blockWidth` sitting immediately to
    /// its left ends up entirely left of the usable area.
    public static func hideWidth(
        lineRightEdge: CGFloat,
        blockWidth: CGFloat,
        in geometry: MenuBarGeometry
    ) -> CGFloat {
        let needed = (lineRightEdge - geometry.usableMinX) + blockWidth
        return min(max(needed, showWidth), maxLineWidth)
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter GeometryTests`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/CurtainCore/Geometry.swift Tests/CurtainCoreTests/GeometryTests.swift
git commit -m "feat: menu bar geometry with an empirical notch dead zone"
```

---

### Task 2: CurtainCore yield session

**Files:**
- Create: `Sources/CurtainCore/YieldSession.swift`
- Create: `Tests/CurtainCoreTests/YieldSessionTests.swift`

**Interfaces:**
- Produces: `YieldSession(token:ttl:startedAt:)`, `.isExpired(at:)`, `.extended(at:by:)`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import CurtainCore

final class YieldSessionTests: XCTestCase {
    func testNotExpiredBeforeTTL() {
        let s = YieldSession(token: "t", ttl: 8, startedAt: 100)
        XCTAssertFalse(s.isExpired(at: 107))
    }

    func testExpiredAtTTL() {
        let s = YieldSession(token: "t", ttl: 8, startedAt: 100)
        XCTAssertTrue(s.isExpired(at: 108))
    }

    func testExtendingPushesTheDeadlineOut() {
        let s = YieldSession(token: "t", ttl: 8, startedAt: 100).extended(at: 105, by: 8)
        XCTAssertFalse(s.isExpired(at: 112))
        XCTAssertTrue(s.isExpired(at: 113))
    }

    func testExtendingKeepsTheToken() {
        let s = YieldSession(token: "abc", ttl: 8, startedAt: 100).extended(at: 105, by: 8)
        XCTAssertEqual(s.token, "abc")
    }
}
```

- [ ] **Step 2: Run to verify it fails** — `swift test --filter YieldSessionTests`, expect "cannot find 'YieldSession'".

- [ ] **Step 3: Implement**

```swift
import Foundation

/// One peek. Carries its own deadline so both ends — the broadcaster and every
/// listening app — can decide to restore without further messages.
public struct YieldSession: Equatable, Sendable {
    public let token: String
    public let ttl: TimeInterval
    public let startedAt: TimeInterval

    public init(token: String, ttl: TimeInterval, startedAt: TimeInterval) {
        self.token = token
        self.ttl = ttl
        self.startedAt = startedAt
    }

    public func isExpired(at now: TimeInterval) -> Bool { now >= startedAt + ttl }

    /// Restarts the clock from `now` — used when the user clicks inside the
    /// revealed block, so reading a menu does not get cut off.
    public func extended(at now: TimeInterval, by ttl: TimeInterval) -> YieldSession {
        YieldSession(token: token, ttl: ttl, startedAt: now)
    }
}
```

- [ ] **Step 4: Run to verify it passes** — `swift test --filter YieldSessionTests`, expect PASS, 4 tests.
- [ ] **Step 5: Commit** — `git commit -m "feat: self-describing yield session with its own deadline"`

---

### Task 3: StatusItemKit yield support

**Files:**
- Modify: `../StatusItemKit/Sources/StatusItemKit/StatusItemController.swift`
- Create: `../StatusItemKit/Sources/StatusItemKit/MenuBarYield.swift`
- Create: `../StatusItemKit/Tests/StatusItemKitTests/MenuBarYieldTests.swift`

**Interfaces:**
- Produces: `MenuBarYield.notificationName`, `MenuBarYield.Payload(state:token:ttl:)` with `.userInfo` / `init?(userInfo:)`, `YieldClient(item:)` with `.start()`, and `StatusItemController.setVisible(_:)`.

- [ ] **Step 1: Write the failing test** — payload round-trips through a `[String: String]` userInfo dictionary, and a malformed dictionary yields `nil`.

```swift
import XCTest
@testable import StatusItemKit

final class MenuBarYieldTests: XCTestCase {
    func testPayloadRoundTrips() {
        let p = MenuBarYield.Payload(state: .yield, token: "abc", ttl: 8)
        let decoded = MenuBarYield.Payload(userInfo: p.userInfo)
        XCTAssertEqual(decoded, p)
    }

    func testMalformedUserInfoIsRejected() {
        XCTAssertNil(MenuBarYield.Payload(userInfo: ["state": "sideways"]))
        XCTAssertNil(MenuBarYield.Payload(userInfo: [:]))
    }

    func testRestorePayloadCarriesNoTTLRequirement() {
        let p = MenuBarYield.Payload(state: .restore, token: "abc", ttl: 0)
        XCTAssertEqual(MenuBarYield.Payload(userInfo: p.userInfo)?.state, .restore)
    }
}
```

- [ ] **Step 2: Run to verify it fails** — `cd ../StatusItemKit && swift test --filter MenuBarYieldTests`.

- [ ] **Step 3: Implement `MenuBarYield.swift` and `setVisible`**

`MenuBarYield` holds the notification name, a `Payload` that encodes to `[String: String]` (distributed notifications only carry property-list values reliably), and `YieldClient`, which on `.yield` sets `isVisible = false` and arms a local `Timer` for the TTL that restores unconditionally, and on `.restore` cancels the timer and restores. `StatusItemController.setVisible(_:)` is a one-line passthrough to `statusItem.isVisible`.

The self-healing timer is the point: if Curtain dies mid-peek, every participating app restores itself.

- [ ] **Step 4: Run to verify it passes** — expect PASS, 3 tests, and the existing StatusItemKit tests still green (`swift test`).
- [ ] **Step 5: Commit in the StatusItemKit repo** — `git commit -m "feat: menu-bar yield protocol with self-healing restore"`

---

### Task 4: Curtain app skeleton with hide/show

**Files:**
- Create: `Sources/Curtain/main.swift`, `Sources/Curtain/Line.swift`
- Create: `Resources/Info.plist`, `scripts/build-app.sh`, `install.sh`, `README.md`, `LICENSE`

**Interfaces:**
- Consumes: `CurtainGeometry.hideWidth(lineRightEdge:blockWidth:in:)`, `CurtainGeometry.showWidth`, `StatusItemController`.
- Produces: `Line.hide()`, `Line.show()`, `Line.rightEdge`, `App.isHidden`.

- [ ] **Step 1: Write `Resources/Info.plist`** — copy KeyLight's, changing executable/identifier/name to `Curtain` / `com.nicholaspsmith.Curtain` / `Curtain`.
- [ ] **Step 2: Write `scripts/build-app.sh`** — `exec ../StatusItemKit/scripts/make-app.sh Curtain "Curtain"`, `chmod +x`.
- [ ] **Step 3: Write `Line.swift`** — owns a bare `NSStatusItem` with no button title; `hide()` sets `length` from `CurtainGeometry.hideWidth`, `show()` sets `CurtainGeometry.showWidth`; `rightEdge` reads `button?.window?.frame.maxX`.
- [ ] **Step 4: Write `main.swift`** — `.accessory` policy, a `StatusItemController` handle with menu rows Peek / Settings… / Start at Login / Quit, and the line. Handle click toggles hide/show.
- [ ] **Step 5: Build and verify manually** — `./install.sh`, quit Ice first, confirm the icons left of the line vanish and return.
- [ ] **Step 6: Commit** — `git commit -m "feat: curtain line and handle with hide/show"`

---

### Task 5: AX menu-bar reader and the stranded-icon watchdog

**Files:**
- Create: `Sources/Curtain/AXMenuBar.swift`, `Sources/Curtain/Watchdog.swift`
- Modify: `Sources/Curtain/main.swift`

**Interfaces:**
- Consumes: `CurtainGeometry.placement(of:in:)`, `ItemFrame`, `MenuBarGeometry`.
- Produces: `AXMenuBar.items() -> [MenuBarItem]` where `MenuBarItem` is `(bundleID: String?, name: String, pid: pid_t, frame: ItemFrame)`; `Watchdog.stranded() -> [MenuBarItem]`.

- [ ] **Step 1: Write `AXMenuBar.swift`** — for each `NSWorkspace.shared.runningApplications`, create an `AXUIElementCreateApplication(pid)`, read `kAXMenuBarAttribute` **and** the extras bar: accessory apps expose the item at menu bar index 0, regular apps at index 1. Read each item's `kAXPositionAttribute` / `kAXSizeAttribute` into an `ItemFrame`. Skip apps that expose nothing (Mullvad, Raycast) — they are hide-only by design.
- [ ] **Step 2: Write `Watchdog.swift`** — build `MenuBarGeometry` from `NSScreen.main` (`auxiliaryTopRightArea?.minX ?? 0`, `frame.maxX`), map every item through `CurtainGeometry.placement`, return those in `.deadZone`.
- [ ] **Step 3: Surface it** — the handle's menu gains a warning row per stranded item ("⚠ <name> is in the notch dead zone"); rescan on `didChangeScreenParametersNotification` and on each menu open.
- [ ] **Step 4: Verify manually** — with KeyLight dragged into the sliver, the warning appears; dragged clear, it disappears.
- [ ] **Step 5: Commit** — `git commit -m "feat: warn when an icon lands in the notch dead zone"`

---

### Task 6: Peek

**Files:**
- Create: `Sources/Curtain/Peek.swift`
- Modify: `Sources/Curtain/main.swift`
- Modify: `../keylight-menubar/Sources/KeyLight/main.swift`, `../vpn-dns-menubar/Sources/*/main.swift`, `../battery-time-menubar/Sources/*/main.swift`, `../MacOS_Process_Monitor/Sources/*/main.swift`

**Interfaces:**
- Consumes: `YieldSession`, `MenuBarYield.Payload`, `Line.show()/hide()`.
- Produces: `Peek.begin()`, `Peek.end()`, `Peek.extend()`.

- [ ] **Step 1: Write `Peek.swift`** — `begin()` posts `.yield` with a fresh `YieldSession`, waits one runloop turn, then calls `Line.show()`; `end()` calls `Line.hide()` then posts `.restore`. A local timer ends the peek at TTL.
- [ ] **Step 2: Extend on click** — `NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown)` inside the menu-bar strip calls `extend()`.
- [ ] **Step 3: Opt each participating app in** — one line in `applicationDidFinishLaunching`: `YieldClient(item: status).start()`. Do KeyLight first, verify, then the other three.
- [ ] **Step 4: Verify manually** — peek reveals the whole hidden block; killing Curtain mid-peek restores every icon within the TTL.
- [ ] **Step 5: Commit** — one commit in each repo, `git commit -m "feat: yield the status item during a curtain peek"`

---

### Task 7: Verified arranging and settings

Blocked on Task 0's result.

**Files:**
- Create: `Sources/Curtain/Arranger.swift`, `Sources/Curtain/SettingsWindow.swift`
- Create: `Sources/CurtainCore/HiddenSet.swift`, `Tests/CurtainCoreTests/HiddenSetTests.swift`

**Interfaces:**
- Consumes: `AXMenuBar.items()`, `CurtainGeometry.placement(of:in:)`.
- Produces: `HiddenSet.load(from:)/save(_:to:)` over `[String]` bundle IDs; `Arranger.move(_ item: MenuBarItem, leftOf x: CGFloat) -> Result<ItemFrame, ArrangeError>`.

- [ ] **Step 1: Write failing tests for `HiddenSet`** — round-trips through an isolated `UserDefaults(suiteName:)`, unknown values are dropped, following `IconStyleTests`' isolation pattern.
- [ ] **Step 2: Run, implement, run** — same defaults-backed shape as `IconStyleStore`.
- [ ] **Step 3: Write `Arranger.swift`** — synthesize the Cmd-drag proven in Task 0, then **read the frame back** via `AXMenuBar`; if it is not left of the line, retry once; if it still is not, return `.failure(.didNotLand(name:))`. Never leave an item in `.deadZone`.
- [ ] **Step 4: Write `SettingsWindow.swift`** — a checkbox per AX-visible menu-bar app, an "Arrange now" button, and an explicit note listing AX-opaque apps that must be dragged by hand.
- [ ] **Step 5: Verify manually** against the real set (UA pair, Tailscale), Ice quit.
- [ ] **Step 6: Commit** — `git commit -m "feat: verified arranging with a checkbox settings list"`

---

### Task 8: Migration off Ice

**Files:**
- Create: `scripts/snapshot-positions.sh`, `scripts/restore-positions.sh`
- Modify: `README.md`

- [ ] **Step 1: Write `snapshot-positions.sh`** — walk `~/Library/Preferences/*.plist`, grep every `NSStatusItem Preferred Position*` key, and emit a runnable `restore-positions.sh` of `defaults write` lines plus the list of apps to relaunch.
- [ ] **Step 2: Run it and keep the output** in `~/Code/menubar-curtain/` (gitignored — it contains only local positions but has no business in a public repo).
- [ ] **Step 3: Cut over** — quit Ice, disable its login item, launch Curtain, arrange, confirm every icon is where it should be and none is stranded.
- [ ] **Step 4: Document rollback in `README.md`** — relaunch Ice, run the restore script.
- [ ] **Step 5: Commit** — `git commit -m "feat: snapshot and restore status item positions for the Ice cutover"`

---

## Self-Review

**Spec coverage:** line/handle → Task 4; `CurtainCore` geometry → Task 1; yield transport and self-heal → Tasks 2, 3, 6; verified arranging → Tasks 0, 7; watchdog → Task 5; migration → Task 8; unit tests → Tasks 1, 2, 3, 7; integration rig and panel (v2) are deliberately out of this plan's scope — the rig is folded into the manual verification steps of Tasks 4–7, and the panel is spec'd as v2.

**Placeholders:** none — every code step carries real code or an exact file-level instruction.

**Type consistency:** `ItemFrame`, `MenuBarGeometry`, `Placement`, `CurtainGeometry.*`, `YieldSession`, `MenuBarYield.Payload`, `MenuBarItem`, `HiddenSet` are each defined once and referenced with the same names and signatures throughout.
