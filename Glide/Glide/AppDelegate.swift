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
    private let windowCycler = WindowCycler()
    private let layoutManager = LayoutManager()
    private var preferencesWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[Glide][app] applicationDidFinishLaunching")

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

        setupStatusItem()
        print("[Glide][app] status item ready")
    }

    // MARK: action dispatch

    private func perform(_ action: HotkeyAction) {
        switch action {
        case .snap(let target):
            windows.snap(target, animated: settings.animateSnap)
        case .moveToNextDisplay:
            windows.moveToAdjacentDisplay(forward: true, animated: settings.animateSnap)
        case .moveToPreviousDisplay:
            windows.moveToAdjacentDisplay(forward: false, animated: settings.animateSnap)
        case .cycleWindow:
            windowCycler.cycleForward()
        case .saveLayout:
            layoutManager.saveLayout()
        case .restoreLayout:
            layoutManager.restoreLayout()
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
                  selector: #selector(handleMoveNextDisplay), enabled: trusted)
        addAction(to: menu, title: "Move Window to Previous Display",
                  selector: #selector(handleMovePreviousDisplay), enabled: trusted)
        addAction(to: menu, title: "Cycle to Next Window",
                  selector: #selector(handleCycleWindow), enabled: trusted)

        menu.addItem(.separator())

        addAction(to: menu, title: "Save Layout",
                  selector: #selector(handleSaveLayout), enabled: trusted)
        addAction(to: menu, title: "Restore Layout",
                  selector: #selector(handleRestoreLayout),
                  enabled: trusted && layoutManager.hasSavedLayout)

        menu.addItem(.separator())

        addAction(to: menu, title: "Preferences…",   selector: #selector(handlePreferences), keyEquivalent: ",")
        addAction(to: menu, title: "Refresh Status", selector: #selector(handleRefresh))
        addAction(to: menu, title: "About Glide",    selector: #selector(handleAbout))
        addAction(to: menu, title: "Quit Glide",     selector: #selector(handleQuit), keyEquivalent: "q")
    }

    private func addAction(to menu: NSMenu, title: String, selector: Selector,
                           keyEquivalent: String = "", enabled: Bool = true) {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: keyEquivalent)
        item.target = self
        item.isEnabled = enabled
        menu.addItem(item)
    }

    private func addSnap(to menu: NSMenu, title: String, target: SnapTarget) {
        let item = NSMenuItem(title: title, action: #selector(handleSnap(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = target
        menu.addItem(item)
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

    @objc private func handleSaveLayout() {
        layoutManager.saveLayout()
    }

    @objc private func handleRestoreLayout() {
        layoutManager.restoreLayout()
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
