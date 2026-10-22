//
//  AppDelegate.swift
//  Glide
//

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let permission = AccessibilityPermission()
    private let settings = AppSettings()
    private let shortcuts = ShortcutStore()
    private let windows = WindowManager()
    private var gestures: GestureMonitor!
    private var hotkeys: HotkeyManager!
    private var edgeSnap: EdgeSnapController!
    private let windowCycler = WindowCycler()
    private var preferencesWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[Glide][app] applicationDidFinishLaunching")

        // Every AX call is a synchronous round-trip to another app, and the
        // default timeout is ~6 s — one busy or hung app would freeze Glide (and
        // every gesture/hotkey) that long. Set on the system-wide element, the
        // timeout applies to all AX elements.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.25)

        gestures = GestureMonitor(windows: windows, settings: settings)
        gestures.onSwipe = { [windows, settings] target, window in
            windows.snap(target, window: window, animated: settings.animateSnap)
        }
        gestures.onMoveToDisplay = { [windows, settings] forward, window in
            windows.moveToAdjacentDisplay(forward: forward, window: window, animated: settings.animateSnap)
        }
        gestures.start()

        hotkeys = HotkeyManager(store: shortcuts)
        hotkeys.onAction = { [weak self] action in
            self?.perform(action)
        }
        hotkeys.start()

        edgeSnap = EdgeSnapController(windows: windows, settings: settings)
        edgeSnap.start()

        setupStatusItem()
        print("[Glide][app] status item ready")
    }

    // MARK: action dispatch

    private func perform(_ action: HotkeyAction) {
        switch action {
        case .snap(let target):
            windows.snap(target, animated: settings.animateSnap, cycleSize: settings.sizeCycleEnabled)
        case .moveToNextDisplay:
            windows.moveToAdjacentDisplay(forward: true, animated: settings.animateSnap)
        case .moveToPreviousDisplay:
            windows.moveToAdjacentDisplay(forward: false, animated: settings.animateSnap)
        case .cycleWindow:
            windowCycler.cycleForward()
        case .hideOthers:
            hideOtherApps()
        case .hideAll:
            hideAllApps()
        }
    }

    private func hideOtherApps() {
        let front = NSWorkspace.shared.frontmostApplication
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && app != front {
            app.hide()
        }
    }

    private func hideAllApps() {
        // macOS always keeps one app frontmost — hiding the front app just
        // promotes another. So first move focus to Finder (the desktop), then
        // hide every real app. What "stays open" is then just the desktop.
        let regular = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        if let finder = regular.first(where: { $0.bundleIdentifier == "com.apple.finder" }) {
            finder.activate()
            for app in regular where app != finder {
                app.hide()
            }
        } else {
            NSApp.activate(ignoringOtherApps: true)
            for app in regular {
                app.hide()
            }
        }
    }

    // MARK: status item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        statusItem = item
        refreshIcon()
    }

    private func refreshIcon() {
        guard let button = statusItem?.button else { return }
        let name = permission.isTrusted ? "rectangle.3.group" : "exclamationmark.triangle.fill"
        button.image = NSImage(systemSymbolName: name, accessibilityDescription: "Glide")
    }

    // MARK: menu construction

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let trusted = permission.isTrusted

        // Permission status
        if trusted {
            let granted = NSMenuItem(title: "Accessibility access granted", action: nil, keyEquivalent: "")
            granted.isEnabled = false
            menu.addItem(granted)
        } else {
            let required = NSMenuItem(title: "Accessibility access required", action: nil, keyEquivalent: "")
            required.isEnabled = false
            menu.addItem(required)
            addAction(to: menu, title: "Request Access…", selector: #selector(handleRequestAccess))
            addAction(to: menu, title: "Open System Settings", selector: #selector(handleOpenSettings))
        }

        menu.addItem(.separator())

        // Reverse Scrolling toggle
        let toggle = NSMenuItem(
            title: "Reverse Scrolling",
            action: #selector(handleToggleReverseScrolling),
            keyEquivalent: ""
        )
        toggle.target = self
        toggle.state = settings.reverseScrolling ? .on : .off
        menu.addItem(toggle)

        menu.addItem(.separator())

        // Snap actions submenu
        let snapMenu = NSMenu(title: "Snap Window")
        addSnap(to: snapMenu, title: "Left",   target: .leftHalf)
        addSnap(to: snapMenu, title: "Right",  target: .rightHalf)
        addSnap(to: snapMenu, title: "Top",    target: .topHalf)
        addSnap(to: snapMenu, title: "Bottom", target: .bottomHalf)
        snapMenu.addItem(.separator())
        addSnap(to: snapMenu, title: "Top-Left Quadrant",     target: .topLeftQuadrant)
        addSnap(to: snapMenu, title: "Top-Right Quadrant",    target: .topRightQuadrant)
        addSnap(to: snapMenu, title: "Bottom-Left Quadrant",  target: .bottomLeftQuadrant)
        addSnap(to: snapMenu, title: "Bottom-Right Quadrant", target: .bottomRightQuadrant)
        snapMenu.addItem(.separator())
        addSnap(to: snapMenu, title: "Left Third",      target: .leftThird)
        addSnap(to: snapMenu, title: "Middle Third",    target: .middleThird)
        addSnap(to: snapMenu, title: "Right Third",     target: .rightThird)
        addSnap(to: snapMenu, title: "Left Two-Thirds", target: .leftTwoThirds)
        addSnap(to: snapMenu, title: "Right Two-Thirds",target: .rightTwoThirds)
        snapMenu.addItem(.separator())
        addSnap(to: snapMenu, title: "Center",      target: .center)
        addSnap(to: snapMenu, title: "Fill Screen", target: .full)

        let snapItem = NSMenuItem(title: "Snap Window", action: nil, keyEquivalent: "")
        snapItem.submenu = snapMenu
        snapItem.isEnabled = trusted
        menu.addItem(snapItem)

        addAction(to: menu, title: "Move Window to Next Display",
                  selector: #selector(handleMoveNextDisplay), enabled: trusted,
                  actionID: .moveNextDisplay)
        addAction(to: menu, title: "Move Window to Previous Display",
                  selector: #selector(handleMovePreviousDisplay), enabled: trusted,
                  actionID: .movePreviousDisplay)
        addAction(to: menu, title: "Cycle to Next Window",
                  selector: #selector(handleCycleWindow), enabled: trusted,
                  actionID: .cycleWindow)

        menu.addItem(.separator())

        // Hiding apps doesn't need Accessibility, so these stay enabled.
        addAction(to: menu, title: "Hide Other Apps",
                  selector: #selector(handleHideOthers), actionID: .hideOthers)
        addAction(to: menu, title: "Hide All Apps",
                  selector: #selector(handleHideAll), actionID: .hideAll)

        menu.addItem(.separator())

        addAction(to: menu, title: "Preferences…",   selector: #selector(handlePreferences), keyEquivalent: ",")
        addAction(to: menu, title: "Refresh Status", selector: #selector(handleRefresh))
        addAction(to: menu, title: "About Glide",    selector: #selector(handleAbout))
        addAction(to: menu, title: "Quit Glide",     selector: #selector(handleQuit), keyEquivalent: "q")
    }

    private func addAction(to menu: NSMenu, title: String, selector: Selector,
                           keyEquivalent: String = "", enabled: Bool = true,
                           actionID: HotkeyActionID? = nil) {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: keyEquivalent)
        item.target = self
        item.isEnabled = enabled
        // Skip the shortcut hint when disabled — an attributedTitle suppresses
        // the system's automatic grey-out.
        if enabled, let attr = shortcutHintTitle(title, actionID: actionID, tabStop: 280) {
            item.attributedTitle = attr
        }
        menu.addItem(item)
    }

    private func addSnap(to menu: NSMenu, title: String, target: SnapTarget) {
        let item = NSMenuItem(title: title, action: #selector(handleSnap(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = target
        if let attr = shortcutHintTitle(title, actionID: .forSnap(target), tabStop: 200) {
            item.attributedTitle = attr
        }
        menu.addItem(item)
    }

    /// Builds a menu title with the action's current shortcut right-aligned in
    /// secondary color. Display only — no `keyEquivalent`, so it can't fire
    /// alongside the global Carbon hotkey. Returns nil when the action is unbound.
    private func shortcutHintTitle(_ title: String, actionID: HotkeyActionID?,
                                   tabStop: CGFloat) -> NSAttributedString? {
        guard let actionID else { return nil }
        return shortcutHintTitle(title, shortcut: shortcuts.shortcut(for: actionID), tabStop: tabStop)
    }

    private func shortcutHintTitle(_ title: String, shortcut: Shortcut?,
                                   tabStop: CGFloat) -> NSAttributedString? {
        guard let shortcut else { return nil }
        let para = NSMutableParagraphStyle()
        para.tabStops = [NSTextTab(textAlignment: .right, location: tabStop)]
        let menuFont = NSFont.menuFont(ofSize: 0)
        let result = NSMutableAttributedString(
            string: title + "\t",
            attributes: [.font: menuFont, .paragraphStyle: para]
        )
        result.append(NSAttributedString(
            string: shortcut.displayString,
            attributes: [.font: menuFont, .paragraphStyle: para,
                         .foregroundColor: NSColor.secondaryLabelColor]
        ))
        return result
    }

    // MARK: menu actions

    @objc private func handleSnap(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? SnapTarget else { return }
        windows.snap(target, animated: settings.animateSnap)
    }

    @objc private func handleMoveNextDisplay() {
        windows.moveToAdjacentDisplay(forward: true, animated: settings.animateSnap)
    }

    @objc private func handleMovePreviousDisplay() {
        windows.moveToAdjacentDisplay(forward: false, animated: settings.animateSnap)
    }

    @objc private func handleCycleWindow() {
        windowCycler.cycleForward()
    }

    @objc private func handleHideOthers() {
        hideOtherApps()
    }

    @objc private func handleHideAll() {
        hideAllApps()
    }

    @objc private func handleRequestAccess() {
        permission.requestPrompt()
        refreshIcon()
    }

    @objc private func handleOpenSettings() {
        permission.openSystemSettings()
    }

    @objc private func handleToggleReverseScrolling() {
        settings.reverseScrolling.toggle()
    }

    @objc private func handleRefresh() {
        permission.refresh()
        refreshIcon()
    }

    @objc private func handleAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func handleQuit() {
        NSApp.terminate(nil)
    }

    @objc private func handlePreferences() {
        if preferencesWindow == nil {
            let view = PreferencesView(settings: settings, shortcuts: shortcuts)
            let host = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: host)
            window.title = "Glide Preferences"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            preferencesWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        preferencesWindow?.makeKeyAndOrderFront(nil)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        permission.refresh()
        rebuildMenu(menu)
        refreshIcon()
    }
}
