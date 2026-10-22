# Glide — Architecture

A macOS menu-bar window manager (snap, multi-display moves, window cycling,
drag-to-edge Quick Split) driven by keyboard shortcuts and trackpad gestures.
No dock icon, no main window — the entire UI lives in an `NSStatusItem`.

> Build/signing/distribution lives in `DISTRIBUTION.md`. Hard constraints
> (App Sandbox off, no `MenuBarExtra`, etc.) live in `CLAUDE.md` — read those
> before changing entitlements or the app lifecycle.

## Data flow

```
   ┌─ GestureMonitor ─┐   ┌─ HotkeyManager ─┐      (input layer)
   │ scroll-wheel /   │   │ Carbon hotkeys  │◀── ShortcutStore
   │ titlebar swipe   │   │ (user-bound)    │    (bindings, persisted)
   └────────┬─────────┘   └────────┬────────┘         ▲
            │ onSwipe /            │ onAction(HotkeyAction)
            │ onMoveToDisplay      │              edited by
            └──────────┬───────────┘            PreferencesView
                       ▼
                 AppDelegate                         (coordinator)
              · owns every component
              · builds the status-item menu
              · perform(action) dispatch
                       │
        ┌──────────────┼───────────────┐
        ▼              ▼               ▼
  WindowManager   WindowCycler   AccessibilityPermission
  (snap / move /  (raise next    (AXIsProcessTrusted
   animate)        window)        gate + menu icon)
        │                                                ▲
        └─ reads AppSettings (animateSnap,               │
           reverseScrolling) ──── PreferencesView ───────┘
              (@Observable, persisted to UserDefaults)
```

Everything that touches other apps' windows goes through the macOS
**Accessibility (AX) API** and therefore requires the Accessibility grant.
When it's missing, `AppDelegate` shows a warning-triangle status icon and
disables the window actions in the menu.

## Components

| File | Role |
|------|------|
| `GlideApp.swift` | `@main` entry point. Empty hidden `Settings` scene only — the App protocol needs one Scene, but the real UI is the status item. |
| `AppDelegate.swift` | Wires up all components, builds/rebuilds the `NSStatusItem` menu, dispatches `HotkeyAction`s, owns the Preferences window. The coordinator. |
| `GestureMonitor.swift` | Global scroll-wheel monitor. Detects a 2-finger swipe that *starts on a window's title bar* and maps swipe direction → `SnapTarget` (or ⌘+swipe → adjacent display). |
| `HotkeyManager.swift` | Registers the user's bindings as **Carbon hotkeys** (`RegisterEventHotKey`) — these *consume* the key event, unlike an NSEvent monitor. Re-registers on every `ShortcutStore` change. Maps fired hotkey → `HotkeyAction`. |
| `Shortcut.swift` | Value types: `Shortcut` (keyCode + modifiers, with Carbon-mask and display-glyph helpers) and `HotkeyActionID` (every bindable action, its `HotkeyAction`, title, and the factory `defaultBindings`). |
| `ShortcutStore.swift` | `@Observable` source of truth for `[HotkeyActionID: Shortcut]`, persisted as versioned JSON in `UserDefaults`. `assign` steals a combo from any conflicting action; `suspend`/`resume` gate registration during recording. |
| `WindowManager.swift` | The core. Snaps/moves the focused (or a given) window via AX, with a `CADisplayLink`-driven eased animation. Defines `SnapTarget` and its geometry. |
| `WindowCycler.swift` | Window-level alternative to ⌘-Tab: raises the next standard window across all regular apps in a stable order. |
| `EdgeSnapController.swift` | Quick Split: arms on a global mouse-down over a title bar, polls the cursor until release, shows a zone overlay near screen edges/corners and snaps on release. |
| `AccessibilityPermission.swift` | `@Observable` wrapper around `AXIsProcessTrusted()`; drives the menu icon and gating. |
| `AppSettings.swift` | `@Observable` prefs (`reverseScrolling`, `animateSnap`), persisted to `UserDefaults`. Must never be named `Settings`. |
| `PreferencesView.swift` | The only SwiftUI view. Toggles + an editable shortcut recorder (one row per `HotkeyActionID`) + launch-at-login via `SMAppService`. |

## Things that will bite you if you don't know them

- **Two coordinate systems.** AX uses a top-left origin; Cocoa/`NSScreen` uses
  bottom-left. `WindowManager` converts in `currentCocoaFrame` / `setFrame`
  using `primary.frame.maxY`. `SnapTarget.rect` works in Cocoa (visibleFrame)
  space. Mixing them silently flips windows vertically.
- **Animation uses `CADisplayLink` via `NSScreen.displayLink(target:selector:)`**
  — the iOS `CADisplayLink(target:selector:)` initializer is unavailable on
  macOS. Interpolation targets `link.targetTimestamp` (not `timestamp`) to
  cancel callback→display latency. See `WindowManager.tickAnimation`.
- **`setFrame` sets size *before* position** so a window that must both shrink
  and move stays within screen bounds during the move.
- **Keep AX off the hot paths.** Every AX call is a synchronous round-trip
  into another app's main thread. The global click/scroll monitors therefore
  ask the WindowServer first (`WindowManager.mayBeTitleBar`, bounds + layer
  only — never window names, which would need Screen Recording) and only
  hit-test via AX when the cursor really is on a title bar. A global 0.25 s
  AX messaging timeout (set in `AppDelegate`) stops a hung app from freezing
  Glide; animations skip unchanged attributes, switch off
  `AXEnhancedUserInterface` while moving, and jump to the end if the app
  can't keep up.
- **The grant is gated everywhere.** New window features must check
  `permission.isTrusted` and disable their menu items when false, mirroring the
  existing actions in `rebuildMenu`.
- **Signing is certificate-based, not ad-hoc**, so the Accessibility grant
  survives rebuilds (see `DISTRIBUTION.md`). Don't revert `build-release.sh` to
  `codesign --sign -`.
- **Carbon hotkeys fire system-wide regardless of focus**, so while the
  recorder is capturing keys, `ShortcutStore.suspend()` unregisters them all —
  otherwise pressing an already-bound combo would trigger its action instead of
  being recorded. `RegisterEventHotKey` also *fails silently* for OS-reserved
  combos (⌘Space, ⌘Tab…); those land in `failedRegistrations` and the recorder
  row shows a ⚠️.
- **Launching the binary straight from a terminal makes `AXIsProcessTrusted()`
  return false** even when the grant exists — TCC attributes Accessibility to
  the terminal, not Glide. Always test the grant via Finder/`open`, not
  `./Glide.app/Contents/MacOS/Glide`.

## Adding a new window action (the common change)

1. Add a case to `SnapTarget` (+ its `rect`) or to `HotkeyAction`.
2. Add a matching `HotkeyActionID` case (with its `action`, `title`, and an
   entry in `defaultBindings` if it should ship with a key) — the recorder row
   and hotkey registration come for free. Optionally add a gesture in
   `GestureMonitor.decideSwipeTarget`.
3. Handle it in `AppDelegate.perform` and add a menu item in `rebuildMenu`
   (gated on `permission.isTrusted`).
