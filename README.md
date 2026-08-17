# Curtain

Hides a block of macOS menu-bar icons — and **cannot strand one**, because it
never writes another app's position during normal operation.

## Why

On 2026-08-16 a menu-bar icon vanished. The app was perfectly healthy: process
alive, status item present, the accessibility API reporting an enabled 32×24
slot. The slot simply sat at x=837 — nine points clear of the notch — and that
sliver renders nothing. Ice had dragged it there and never checked.

Ice's binary shows the mechanism: private CoreGraphics calls to read geometry, a
synthesized ⌘-drag to move items, and no read-back at all. Position is rewritten
continuously, silently, with no feedback loop. Quitting Ice makes the same
mistake in the other direction — it restored three icons straight into the notch,
all invisible.

## How this differs

Curtain hides by **width**. A status item of its own grows leftward, sliding its
neighbours off the display. Items to its right never move, and no other app's
state is touched — so the failure class is structurally absent rather than
carefully avoided.

The one exception is arranging, which happens at setup only, never continuously,
and always reads back where the icon landed.

## Using it

| | |
|---|---|
| **Left click** | the hidden icons, each with its own live menu |
| **Right click** | Manage Icons, reveal behaviour, Start at Login, Quit |

A hidden app's submenu is its *real* menu, read over the accessibility API while
its icon sits off-screen — so a hidden app stays usable without anything moving.
Apps that publish no menu open directly instead.

## Install

```sh
./install.sh
```

Builds, symlinks into `~/Applications`, and launches. Needs Accessibility (see
the first-run notes it prints). Requires [StatusItemKit](https://github.com/nicholaspsmith/StatusItemKit)
and [HotkeyKit](https://github.com/nicholaspsmith/HotkeyKit) checked out
alongside this repo.

## Migrating off Ice

Ice and Curtain both manage the same icons, so running both will strand one.

```sh
./scripts/snapshot-positions.sh     # capture every icon's position first
```

Then quit Ice and stop it launching at login. Ice registers via `SMAppService`,
so there is no LaunchAgent to remove — either switch it off in System Settings ▸
General ▸ Login Items, or move the app aside:

```sh
mv /Applications/Ice.app ~/.disabled-apps/
```

**Rollback** is the reverse: move `Ice.app` back, run the generated
`restore-positions.sh`, and relaunch the affected apps (positions are read when
an app creates its status item, so each one needs a restart to pick them up).

## Known limits

- **The bar has a capacity.** Making an app visible when the strip is already
  full pushes something into the notch sliver, where it draws nothing. Curtain
  names whatever lands there, but it cannot create room — you have to hide
  something in exchange.
- **Some apps are invisible to accessibility.** Mullvad and Raycast publish no
  status item at all, so they can be hidden but not listed or arranged for.
- **Shortcuts depend on the app.** Rows show key equivalents where an app sets
  them; Rectangle registers global hotkeys instead, so it publishes none.
- **Main display only.**

## Design notes

`docs/superpowers/` carries the design and the plan, including the measurements
behind every constant — why a status item must fit entirely right of the notch to
render at all, why an app cannot trust its own item's window frame, and why
yielding by width rather than `isVisible` is the only way to keep a placement.
