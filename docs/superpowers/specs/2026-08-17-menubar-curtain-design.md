# Menu Bar Curtain — design

Date: 2026-08-17
Status: approved, implementing

## Goal

Replace Ice with a menu-bar manager that hides third-party clutter (the UA pair,
Mullvad, Tailscale, VLC, LibreOffice, LuLu, Raycast, vidsnatch) and **cannot
strand an icon**, because it never rewrites another app's position during normal
operation.

## Background — why replace Ice

On 2026-08-16 KeyLight's menu-bar icon disappeared. The app was healthy: process
alive, `NSStatusItem` present, AX reporting an enabled 32×24 slot. The slot had
simply been placed at x=837 — 9pt clear of the notch boundary at x=828 — and that
notch-adjacent sliver renders nothing. Repositioning it in Ice moved it to x=919
and it drew normally (`NSStatusItem Preferred Position` went 566 → 548).

Ice's binary shows the mechanism: it reads item geometry with private CGS calls
(`CGSGetProcessMenuBarWindowList`, `CGSGetScreenRectForWindow`,
`CGSCopyActiveMenuBarDisplayIdentifier`) and moves items by synthesizing a
Cmd-drag (`CGEventCreateMouseEvent`/`CGEventPost`/`CGEventPostToPid`, wrapped in
`CGEventSourceSetLocalEventsFilterDuringSuppressionState`). macOS persists the
result into the *target app's* preferences. The drag is fire-and-forget: nothing
reads back where the item landed, so an icon dropped in the dead zone is silently
gone. That is a design property, not a misconfiguration.

## Probe findings (all measured on this machine, 2026-08-16/17)

1. **Expander reflow works on macOS 26.** Growing one status item from 36 to
   412pt moved its left neighbour from x=-4394 to x=-4770 — displaced by exactly
   the width gained — while its right neighbour did not move. Collapsing restored
   both exactly. `length = 10000` clamps to ~5012 actual width.
2. **Ice hijacks new status items within ~2s**, dragging them to its hidden
   section (x≈-4314). It must be fully quit, login item disabled, or it fights us.
3. **AX reads off-screen item geometry.** Accessory (`LSUIElement`) apps expose
   the item at `menu bar 1`; regular apps at `menu bar 2`. Measured while hidden:
   Tailscale x=-4253 w=24, UA Mixer Engine x=-4225 w=44, UA Connect x=-4183 w=36.
4. **AX can enumerate and drive an off-screen item's menu while it is invisible.**
   Verified end to end against a fixture app (menu rows read by name, a chosen row
   clicked, the target's action handler fired) and read against the real apps:
   Tailscale (Settings…, Open Tailscale, Quit), UA Mixer Engine (Console, Console
   Settings, Console Output Meters, UAD Meter & Control Panel, Browse Plug-Ins…),
   UA Connect (Open UA Connect, UAD Labs, Leave Feedback, Quit).
5. **Two coverage gaps.** Mullvad exposes no AX-visible process at all; Raycast
   exposes no AX status item. Both are hide-only — no panel, no scripted drag.
6. **Geometry on the built-in display:** frame 1496×967, notch occupies
   x=668–828 (`auxiliaryTopRightArea` starts at 828), visible cluster spans
   871–1498, leaving **43 free points**. The 9 hidden icons total ≈280pt, so a
   plain in-place "show all" is impossible here — hence peek.

## Phase 0 result (measured 2026-08-17)

**Synthesized Cmd-drag works.** Dragging ProcessMonitor's item from x=1166 to a
requested x=1080 landed it at x=1071 (within 9pt), swapped it cleanly with its
neighbour, and **persisted**: its `NSStatusItem Preferred Position` went 248 →
296. Dragging it back restored the original order exactly. Task 7 proceeds as
specced.

Three details that constrain the implementation:

1. **AX coordinates feed `CGEvent` directly.** Both use a top-left origin, so an
   item reported by AX at `(1166, 2)` with size `(37, 24)` is pressed at
   `(1184, 14)` with no conversion. (`NSWindow.frame` does *not* share this
   origin — converting from AppKit was the bug in the first probe attempt.)
2. **An off-screen item cannot be dragged at all.** The cursor clamps to the
   screen, so a press at x=-4300 never reaches the item. Arranging must therefore
   run with the block *shown*, never while hidden.
3. **A jammed bar places new items left of the notch.** With Ice quit and all 9
   icons back, a fresh fixture item landed at x=629 — left of the notch, where it
   is neither visible nor pressable.

**Ice restores blindly on quit, straight into the dead zone.** Quitting Ice
returned Tailscale, UA Mixer Engine and UA Connect from x≈-4300 to x=722, 750 and
792 — all inside the notch (which starts at 668 and ends at 828), all invisible.
This is the 2026-08-16 bug happening three times at once, it confirms the
migration risk, and it is precisely what the watchdog exists to catch. Run
`scripts/snapshot-positions.sh` before any cutover.

## Implementation findings (2026-08-17)

Three constraints discovered while building the curtain item, each of which
changed the design:

1. **Place narrow, then grow.** A status item created — or re-placed — while
   already wide does not fit at its ranked position, so macOS puts it wherever it
   will go and shoves every other icon aside. Measured: a 438pt item landed
   *right* of all four of our apps and hid the lot. Created narrow it takes its
   ranked spot, and growing then pins the right edge and pushes only leftward.
   The app therefore shows narrow on launch and on every display change, waits
   1.5s for placement, and only then applies the real state.
2. **Line and handle must be the same item.** With two items, the handle is the
   one a full bar bumps — it landed at x=-208, inside the hidden block, leaving
   no way to unhide. One item, with its control drawn at the right edge, always
   has a reachable control because the right edge never moves.
3. **The width self-corrects.** The first hide computes from a stale right edge
   and overshoots (881pt); the next poll recomputes from the settled edge and
   converges (470pt), stable across subsequent ticks.

**Open:** the chevron does not render. Neither a composited SF Symbol image nor a
right-aligned attributed title produced visible ink at the item's right edge,
though the item itself is present and its menu works. Unverified visually since
the screen locked mid-session; the fallback if right-alignment cannot be made to
work is a narrow always-visible sibling item positioned by a one-time verified
drag (the mechanism Task 7 builds anyway).

## Non-goals

Menu-bar appearance styling, menu-bar search, multiple hidden sections,
continuous position management, per-icon reordering after setup, and
external-display management. The panel (AX-driven menu list) is v2, specced in
outline only.

## Architecture

New repo `~/Code/menubar-curtain` → `Curtain.app`: `LSUIElement`, StatusItemKit
shell, SMAppService "Start at Login", `make-app.sh` with the stable self-signed
identity so the Accessibility grant survives rebuilds.

**Two status items owned by Curtain:**

- **The line** — the expander. No glyph; its width *is* the state. Wide (~2000,
  well under the ~5012 clamp) = hidden; ~1 = shown. Everything to its left is the
  hidden block. Items to its right provably do not move when it grows.
- **The handle** — always visible and clickable. Toggles peek; its menu holds
  Peek, Settings…, Start at Login, Quit, plus any stranded-icon warnings.

**`CurtainCore`** holds every pure function, mirroring the `KeyLightCore` split so
the geometry — the part that caused the original bug — is unit-testable without
AppKit: line width from frames + notch bounds, the dead-zone predicate, drag
target computation, and the yield token/TTL state machine.

**StatusItemKit gains two things:** `StatusItemController.setVisible(_:)` and a
`YieldClient` that listens for the peek broadcast. Each participating app opts in
with one line; nothing else about those apps changes.

**Yield transport: `DistributedNotificationCenter`** (`com.nicholaspsmith.menubar.yield`),
carrying state (`yield`/`restore`), a token, and a TTL. Same-user, instant, no
entitlements, and none of these apps are sandboxed. Rejected: piggybacking on
StatusItemKit's existing 5s poll (up to 5s of lag makes peek unusable) and XPC
(overkill for fire-and-forget).

**HotkeyKit** supplies an optional global hotkey for peek, reusing the trust
plumbing KeyLight already exercises.

## Data flow

**Hide/show:** handle click or hotkey → `CurtainCore` computes the line width →
`statusItem.length` set. One value written, and it is ours.

**Peek:** broadcast `yield` → participating items set `isVisible = false`,
freeing ≈230pt → collapse the line → hidden block slides fully into view → user
clicks a real icon → on TTL expiry or handle click, expand the line, then
broadcast `restore`. Yield-then-collapse on the way in, expand-then-restore on the
way out, so the bar never briefly double-occupies.

**Arranging (setup only):** for each checked app — read its item frame via AX,
synthesize the Cmd-drag to a target x left of the line, **read the frame back**,
retry once if it did not land left of the line, and if it still has not, stop and
name the app in the UI. Nothing is assumed to have worked. After setup, macOS
persists each app's position itself, so a relaunched VLC returns to its arranged
spot with no further drags.

## Error handling

- **Verified drags.** Every synthesized drag is followed by a read-back; failures
  surface by app name rather than leaving an icon somewhere invisible.
- **Stranded-icon watchdog.** On every state change, on
  `didChangeScreenParametersNotification`, and on a slow timer, compare managed
  item frames against `NSScreen.auxiliaryTopRightArea`. Anything in the notch dead
  zone is named in the handle's menu ("⚠ KeyLight is in the notch dead zone").
  Where the item is left of the line, shrinking the line fixes it outright; where
  it is right of the line, reporting it is the whole difference from 2026-08-16.
- **Yield self-heals.** Each `YieldClient` arms a local timer from the TTL and
  restores itself when it expires, regardless of what Curtain does. If Curtain
  crashes or is force-quit mid-peek, the icons come back on their own. No shutdown
  path can leave the menu bar broken.
- **Known rough edge (documented, not solved):** if a peek expires while a
  third-party menu is open, the line re-expands and slides that icon away beneath
  its own menu. macOS menus run a modal event loop that swallows the global
  monitors needed to detect this cleanly; extend-on-click makes it unlikely and
  the recovery is closing the menu. Revisit only if it bites in practice.

## Testing

- **Unit** (`CurtainCoreTests`): line-width computation, dead-zone predicate,
  drag-target math, yield state machine. Pure functions, no AppKit.
- **Integration rig** (`scripts/integration-test.sh`), productized from the
  spikes: launch a fixture status-item app, drive real curtain operations, assert
  resulting frames via AX. Needs a live GUI session so it is not CI-able, but it
  is exactly how every claim above was verified.
- **Manual checklist**: icons visibly render; behaviour on an external display;
  a dock/undock cycle (BetterDisplay has a history of reshuffling on display
  reconfiguration in this setup).

## Migration off Ice

- **Phase 0, before any cutover:** `scripts/snapshot-positions.sh` captures every
  `NSStatusItem Preferred Position` across all preference domains and emits a
  matching `restore-positions.sh` (`defaults write` + relaunch, since positions
  are read at item creation). It is unknown whether Ice restores the 9 apps when
  it quits; the snapshot makes that a non-event either way.
- **Cutover:** quit Ice *and* disable its login item, run Curtain, arrange.
- **Rollback:** relaunch Ice, run the restore script.

## Phases

0. **Drag feasibility** — prove synthesized Cmd-drag on a throwaway item of our
   own, before any settings UI. If unreliable on macOS 26, the design falls back
   to hand-arranging and the checkbox list becomes display-only.
1. `CurtainCore` + line/handle hide-show.
2. Yield/peek across StatusItemKit and the participating apps.
3. Settings UI + verified arranging.
4. Migration scripts + cutover off Ice.
5. *(v2)* AX-driven panel for Tailscale/UA-class apps.

## Known limitations

- Mullvad and Raycast are hide-only: no scripted arranging (drag them by hand
  once), and no panel in v2.
- Apps that open a custom popover instead of an `NSMenu` are also panel-exempt.
- v1 manages the main display only.
- Curtain needs Accessibility; without it, hide/show still works but arranging
  does not.
