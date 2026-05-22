# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Glide is a SwiftUI **macOS** menu-bar app (not iOS, `LSUIElement = YES`, no Dock icon). Bundle ID `com.glide.Glide`. It's a Swish + Wins style window manager: trackpad gestures + global hotkeys snap windows to halves, quadrants, center, fullscreen.

**Module map** (`Glide/Glide/Glide/`):

| File | Role |
|---|---|
| `GlideApp.swift` | `@main` — only wires `@NSApplicationDelegateAdaptor(AppDelegate.self)` and declares an empty `Settings { EmptyView() }` scene (the App protocol requires at least one Scene; we never show it) |
| `AppDelegate.swift` | The real entry point. Owns `NSStatusItem`, builds the `NSMenu` programmatically, instantiates and wires `WindowManager`, `GestureMonitor`, `HotkeyManager`, `AccessibilityPermission`, `AppSettings`. **Do NOT switch back to SwiftUI MenuBarExtra** — see memory [[feedback-menu-activation-hang]] |
| `AccessibilityPermission.swift` | `@Observable` wrapper around `AXIsProcessTrusted()`. The menu re-checks on each `menuNeedsUpdate` rather than via a `didBecomeActiveNotification` observer (that observer caused activation hangs) |
| `AppSettings.swift` | `@Observable` preferences (UserDefaults-backed). Currently just `reverseScrolling` Bool. **Named `AppSettings` — never `Settings`** (collides with SwiftUI's `Settings<Content>` Scene) |
| `WindowManager.swift` | `SnapTarget` enum (halves/quadrants/full/center) + AX-driven window placement. Finds the screen containing the window for multi-monitor correctness |
| `GestureMonitor.swift` | `NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel)` → angle-based swipe recognition (25°-65° → quadrant; long up → full; long down → center). Triggers only when gesture starts on a title-bar region (top 30pt of the window under cursor) |
| `HotkeyManager.swift` | `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)` filtered to exactly Ctrl+Opt. Emits `HotkeyAction` (snap / move-display / cycle / save-restore-layout). **Not Carbon** — `Carbon.InstallEventHandler` interfered with menu bar activation in our setup |
| `WindowCycler.swift` | Window-level Cmd-Tab alternative — enumerates every regular app's standard windows, raises the next in a stable order. No previews (those need Screen Recording) |
| `LayoutManager.swift` | Save/restore all window positions. Snapshots `(bundleID, title, AX-frame)` to UserDefaults; restore matches by bundleID+title, best-effort |
| `PreferencesView.swift` | SwiftUI preferences UI, shown in an AppKit `NSWindow` via `NSHostingController` (opened from the menu). Launch-at-login (`SMAppService`), reverse scrolling, animate toggle, shortcut reference |

**Default global hotkeys** (Ctrl+Opt modifier):
- `←` left half, `→` right half, `↑` top half, `↓` bottom half
- `U` top-left, `I` top-right, `J` bottom-left, `K` bottom-right
- `1/2/3` left/middle/right third, `4/5` left/right two-thirds
- `C` center (60×60), `Return` fill screen
- `M` move window to next display (cycles), `Tab` cycle to next window
- `S` save layout, `R` restore layout

**Trackpad gestures** (on a window's title bar): 2-finger swipe → snap (directional → halves, diagonal → quadrants, long up → full, long down → center). `⌘` held + horizontal swipe → move window to the adjacent display.

**Pinch is removed** — NSEvent magnify monitor + CGEventTap both proved unworkable; full/center are reachable via long swipe, hotkeys, and the menu instead. See memory `project-pinch-deferred`.

## Building a release for distribution

`./build-release.sh` (repo root) builds a Release `Glide.app`, ad-hoc signs it, and produces `~/Desktop/Glide.zip`. The build is **unsigned during xcodebuild then ad-hoc signed manually** — Xcode's inline codesign step fails on extended-attribute "detritus" from the source tree. `DISTRIBUTION.md` has the end-user install steps (Gatekeeper bypass via `xattr -cr`, since there's no paid Developer ID).

## Layout quirk

The Xcode project lives one level below the repo root:

```
Glide/                         <- repo root
  Glide/
    Glide.xcodeproj            <- open this
    Glide/                     <- source folder (GlideApp.swift, ContentView.swift, Assets.xcassets)
```

All `xcodebuild` / `xed` commands must be run from `Glide/` (the inner directory containing `Glide.xcodeproj`), not the repo root.

## Adding source files

The project uses `PBXFileSystemSynchronizedRootGroup` (the Xcode 16+ synchronized-folders feature). **Do not edit `project.pbxproj` to register new Swift files** — any file placed inside `Glide/Glide/Glide/` is picked up automatically. Just create the file in the right folder.

## Build / run / test

From the directory containing `Glide.xcodeproj`:

```bash
# Build (Debug)
xcodebuild -project Glide.xcodeproj -scheme Glide -configuration Debug build

# Build & run in Xcode
xed Glide.xcodeproj      # then ⌘R

# Run tests — no test target exists yet. When one is added:
xcodebuild -project Glide.xcodeproj -scheme Glide test
xcodebuild -project Glide.xcodeproj -scheme Glide test -only-testing:GlideTests/SomeTests/testMethod
```

Deployment target: **macOS 15.6**. Swift 5. SDK = `macosx`.

## Concurrency default

`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is set project-wide, plus `SWIFT_APPROACHABLE_CONCURRENCY = YES`. New types, functions, and closures are **`@MainActor` by default** unless explicitly annotated otherwise (`nonisolated`, `@globalActor`, etc.). Keep this in mind when adding networking, file I/O, or background work — those call sites need explicit off-main isolation.

## Sandbox

**App Sandbox is intentionally OFF** (`ENABLE_APP_SANDBOX = NO`). This is required: AX-based window managers cannot post events or move other apps' windows inside the sandbox, and ad-hoc signed dev builds inside the sandbox also break `AXIsProcessTrusted()`.

The privacy stance (no network, no persistent storage, only Accessibility permission) is now enforced by code review and by **not adding** the corresponding entitlements/APIs — not by the system sandbox. Do not propose re-enabling the sandbox or adding network/file/automation entitlements without explicit user confirmation; those are non-negotiable product constraints.

The leftover `ENABLE_USER_SELECTED_FILES = readonly` and `REGISTER_APP_GROUPS = YES` settings are sandbox-only and ignored at runtime; harmless but can be removed for cleanliness.
