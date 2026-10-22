# Glide — Product Overview

> A briefing document describing what Glide is and what it currently does.
> Intended as self-contained context for research (e.g. comparing Glide against
> other macOS window managers and identifying features worth adopting).

## What it is

Glide is a **macOS menu-bar window manager**. It lets you reposition and resize
windows of *other* apps — snap them to halves/quadrants/thirds, move them across
displays, cycle focus, and hide other apps — driven by **keyboard
shortcuts** and **trackpad gestures**. It has no dock icon and no main window;
its entire UI is a status-bar menu plus a small Preferences window.

It is a personal/indie project, not a commercial product. Current distribution
is a development-signed `.app` shared directly (not on the App Store, not
notarized).

## Positioning & design principles

These are the deliberate constraints that differentiate Glide and should frame
any feature comparison:

- **Single permission model.** Glide requires only **Accessibility** (the macOS
  AX API). It deliberately does **not** use **Screen Recording**, so it cannot
  (and will not) show window thumbnails/previews. This keeps setup to one grant
  and avoids the heavier privacy prompt. Any candidate feature that needs Screen
  Recording is considered out of scope.
- **Lightweight & native.** Pure AppKit/SwiftUI + system APIs. No helper
  daemons, no tiling window-server hacks, no private frameworks.
- **Menu-bar only** (`LSUIElement`). No dock presence; the status item is the
  whole UI.
- **Consuming, customizable hotkeys.** Global shortcuts are registered as Carbon
  hotkeys, so they *consume* the key event (no double-firing in the focused
  app), and every action is rebindable by the user.
- **Non-destructive.** Glide moves/sizes existing windows; it does not manage a
  forced tiling layout or take over the window server.

## Platform & requirements

- **Apple Silicon only** (arm64). Intel Macs are unsupported.
- **macOS 15.6+**.
- **Accessibility** permission required (to read/move other apps' windows).
- App Sandbox is off; the app is not notarized (dev-signed for direct sharing).

## Current features

**Window snapping** (to the screen's visible frame):
- Halves: left, right, top, bottom
- Quadrants: the four corners
- Thirds: left/middle/right third, and left/right two-thirds
- Center (60% centered) and Fill Screen (maximize)
- Snap is animated (toggleable) with a subtle haptic tap on supported trackpads.

**Input methods:**
- **Keyboard:** every action has a user-customizable global shortcut, edited via
  a recorder in Preferences (defaults use ⌃⌥ + arrows/letters/digits). Reserved
  system combos are detected and flagged. The status menu shows each action's
  current shortcut.
- **Trackpad:** a two-finger swipe that starts on a window's **title bar** snaps
  that window in the swipe direction (direction → target mapping, with a
  reverse-scroll option). Holding ⌘ while swiping moves the window to the
  adjacent display instead.

**Multi-display:**
- Move the focused window to the next/previous display, preserving its relative
  position and size.

**Window switching:**
- Cycle focus to the next standard window across all regular apps (a
  window-level alternative to ⌘-Tab). **No previews** (that would need Screen
  Recording) — it simply raises the next window in a stable order.

**Quick Split:**
- Drag a window by its title bar to a screen edge or corner to snap it there,
  with a translucent preview of the target zone.

**App hiding:**
- Hide Other Apps / Hide All Apps, each bindable to a shortcut.

**Other:**
- Launch at login (via `SMAppService`).
- Preferences window with toggles (reverse scrolling, animate movement), the
  shortcut recorder, and a trackpad-gesture cheat sheet.

## How it works (brief)

- Window manipulation uses the **Accessibility API** (`AXUIElement`): read/set
  `kAXPosition`/`kAXSize`, find the focused window, walk the element tree, etc.
- Global shortcuts use **Carbon `RegisterEventHotKey`** (consuming, system-wide).
- Trackpad gestures use a global scroll-wheel monitor that only acts when the
  gesture begins over a window's title bar.
- Animations interpolate the AX frame on a `CADisplayLink` synced to the
  display refresh.

## Current limitations / non-goals

- No window **thumbnails/previews** anywhere (no Screen Recording — by design).
- No **tiling/auto-layout engine** (manual snapping only).
- No saved window layouts (the feature was removed).
- Cycle window switcher has no UI/preview.
- Intel Macs unsupported.

## Under consideration (so research need not re-suggest these)

Being built or actively evaluated, all constrained to Accessibility-only (no
Screen Recording):
- **Dock window actions**: hover a Dock icon to list that app's windows (by
  title, no thumbnails) and close them — feasibility confirmed with AX only.

## Useful comparison axes for research

When evaluating other macOS window managers (e.g. Rectangle, Magnet, Moom,
Swish, Loop, Tiles, Wins, BetterSnapTool, Amethyst, yabai), the most relevant
questions for Glide are:
- Which of their features are achievable with **Accessibility only** (no Screen
  Recording, no private APIs, no daemon)?
- Which fit a **menu-bar, non-tiling, non-destructive** model?
- Which add value without compromising the **one-permission, lightweight** ethos?
