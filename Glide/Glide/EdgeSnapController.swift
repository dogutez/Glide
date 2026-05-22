//
//  EdgeSnapController.swift
//  Glide
//

import AppKit
import ApplicationServices

/// "Quick Split": dragging a window's title bar toward a screen edge or corner
/// snaps it there on release, with a translucent zone preview.
///
/// A global monitor only reliably delivers the initial `leftMouseDown`; the
/// drag/up events are flaky for windows owned by other apps. So we arm on
/// mouse-down over a title bar, then **poll** the cursor and button state until
/// release — no dependence on continuous drag events.
final class EdgeSnapController {
    private let windows: WindowManager
    private let settings: AppSettings

    private var downMonitor: Any?
    private var pollTimer: Timer?

    private var draggedWindow: AXUIElement?
    private var startPoint: CGPoint = .zero
    private var armed = false
    private var currentZone: SnapTarget?
    private var overlay: NSWindow?

    private let activationInset: CGFloat = 8   // cursor distance from edge to trigger
    private let cornerZone: CGFloat = 120      // span along an edge that counts as a corner
    private let dragThreshold: CGFloat = 10    // movement before snapping arms

    init(windows: WindowManager, settings: AppSettings) {
        self.windows = windows
        self.settings = settings
    }

    func start() {
        guard downMonitor == nil else { return }
        downMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            self?.handleMouseDown()
        }
    }

    func stop() {
        if let downMonitor { NSEvent.removeMonitor(downMonitor); self.downMonitor = nil }
        endDrag(snap: false)
    }

    // MARK: drag tracking

    private func handleMouseDown() {
        guard settings.edgeSnapEnabled, pollTimer == nil else { return }
        let location = NSEvent.mouseLocation
        guard let window = windows.titleBarWindow(at: location) else { return }
        draggedWindow = window
        startPoint = location
        armed = false
        currentZone = nil
        // .common mode so polling continues even if the run loop enters an
        // event-tracking mode mid-drag.
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func poll() {
        // Left button released? Finish.
        if NSEvent.pressedMouseButtons & 0x1 == 0 {
            endDrag(snap: true)
            return
        }
        let location = NSEvent.mouseLocation
        if !armed {
            // Require real movement so a plain click on a title bar near an edge
            // doesn't snap.
            if hypot(location.x - startPoint.x, location.y - startPoint.y) > dragThreshold {
                armed = true
            } else {
                return
            }
        }
        let zone = self.zone(for: location)
        if zone != currentZone {
            currentZone = zone
            updateOverlay(for: zone, at: location)
        }
    }

    private func endDrag(snap: Bool) {
        pollTimer?.invalidate()
        pollTimer = nil
        let zone = currentZone
        let window = draggedWindow
        let armedNow = armed
        draggedWindow = nil
        armed = false
        currentZone = nil
        hideOverlay()
        if snap, armedNow, let zone, let window {
            windows.snap(zone, window: window,
                         onScreenContaining: NSEvent.mouseLocation,
                         animated: settings.animateSnap)
        }
    }

    // MARK: zones

    private func zone(for location: CGPoint) -> SnapTarget? {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(location) }) else {
            return nil
        }
        let f = screen.frame  // Cocoa coords: y increases upward, maxY is the top
        let nearLeft = location.x <= f.minX + activationInset
        let nearRight = location.x >= f.maxX - activationInset
        let nearTop = location.y >= f.maxY - activationInset

        if nearLeft {
            if location.y >= f.maxY - cornerZone { return .topLeftQuadrant }
            if location.y <= f.minY + cornerZone { return .bottomLeftQuadrant }
            return .leftHalf
        }
        if nearRight {
            if location.y >= f.maxY - cornerZone { return .topRightQuadrant }
            if location.y <= f.minY + cornerZone { return .bottomRightQuadrant }
            return .rightHalf
        }
        if nearTop {
            if location.x <= f.minX + cornerZone { return .topLeftQuadrant }
            if location.x >= f.maxX - cornerZone { return .topRightQuadrant }
            return .full
        }
        return nil
    }

    // MARK: overlay

    private func updateOverlay(for zone: SnapTarget?, at location: CGPoint) {
        guard let zone,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(location) }) else {
            hideOverlay()
            return
        }
        let frame = zone.rect(in: screen.visibleFrame)
        let window = overlayWindow()
        window.setFrame(frame, display: true)
        window.orderFront(nil)
    }

    private func hideOverlay() {
        overlay?.orderOut(nil)
    }

    private func overlayWindow() -> NSWindow {
        if let overlay { return overlay }
        let window = NSWindow(contentRect: .zero, styleMask: .borderless,
                              backing: .buffered, defer: true)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let view = NSView()
        view.wantsLayer = true
        let layer = view.layer!
        layer.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.25).cgColor
        layer.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.9).cgColor
        layer.borderWidth = 2
        layer.cornerRadius = 10
        window.contentView = view

        overlay = window
        return window
    }
}
