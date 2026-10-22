//
//  WindowManager.swift
//  Glide
//

import AppKit
import ApplicationServices
import QuartzCore

enum SnapTarget: Hashable {
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case topLeftQuadrant
    case topRightQuadrant
    case bottomLeftQuadrant
    case bottomRightQuadrant
    case leftThird
    case middleThird
    case rightThird
    case leftTwoThirds
    case rightTwoThirds
    case full
    case center

    func rect(in visibleFrame: CGRect) -> CGRect {
        let halfW = visibleFrame.width / 2
        let halfH = visibleFrame.height / 2
        let thirdW = visibleFrame.width / 3
        switch self {
        case .leftHalf:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.minY,
                          width: halfW, height: visibleFrame.height)
        case .rightHalf:
            return CGRect(x: visibleFrame.midX, y: visibleFrame.minY,
                          width: halfW, height: visibleFrame.height)
        case .topHalf:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.midY,
                          width: visibleFrame.width, height: halfH)
        case .bottomHalf:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.minY,
                          width: visibleFrame.width, height: halfH)
        case .topLeftQuadrant:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.midY,
                          width: halfW, height: halfH)
        case .topRightQuadrant:
            return CGRect(x: visibleFrame.midX, y: visibleFrame.midY,
                          width: halfW, height: halfH)
        case .bottomLeftQuadrant:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.minY,
                          width: halfW, height: halfH)
        case .bottomRightQuadrant:
            return CGRect(x: visibleFrame.midX, y: visibleFrame.minY,
                          width: halfW, height: halfH)
        case .leftThird:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.minY,
                          width: thirdW, height: visibleFrame.height)
        case .middleThird:
            return CGRect(x: visibleFrame.minX + thirdW, y: visibleFrame.minY,
                          width: thirdW, height: visibleFrame.height)
        case .rightThird:
            return CGRect(x: visibleFrame.minX + 2 * thirdW, y: visibleFrame.minY,
                          width: thirdW, height: visibleFrame.height)
        case .leftTwoThirds:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.minY,
                          width: 2 * thirdW, height: visibleFrame.height)
        case .rightTwoThirds:
            return CGRect(x: visibleFrame.minX + thirdW, y: visibleFrame.minY,
                          width: 2 * thirdW, height: visibleFrame.height)
        case .full:
            return visibleFrame
        case .center:
            let width = visibleFrame.width * 0.6
            let height = visibleFrame.height * 0.6
            return CGRect(x: visibleFrame.midX - width / 2,
                          y: visibleFrame.midY - height / 2,
                          width: width, height: height)
        }
    }
}

final class WindowManager {
    private let titleBarHeight: CGFloat = 30

    // Animation state. CADisplayLink syncs callbacks to display refresh
    // (60 / 120 Hz). Without vsync sync, Timer-based interpolation produces
    // visible tearing/jitter because frame updates land at random points in
    // the refresh cycle.
    private var displayLink: CADisplayLink?
    private var animStart: CGRect = .zero
    private var animEnd: CGRect = .zero
    private var animStartTime: CFTimeInterval = 0
    private let animDuration: CFTimeInterval = 0.18
    private var animWindow: AXUIElement?
    private var animLastWritten: CGRect?
    private var animEnhancedUIApp: AXUIElement?
    private var animActivity: NSObjectProtocol?
    // An app that needs longer than this to apply one AX frame update can't
    // animate smoothly (Electron, huge editors); such windows jump to the end.
    private let slowFrameLimit: CFTimeInterval = 0.025

    // Size-cycle state: repeating the same snap shortcut on the same window
    // within the timeout steps through a sequence of sizes (Rectangle-style).
    private var cycleWindow: AXUIElement?
    private var cycleBase: SnapTarget?
    private var cycleIndex = 0
    private var cycleTime: CFTimeInterval = 0
    private let cycleTimeout: CFTimeInterval = 1.5
    private static let cycleSequences: [SnapTarget: [SnapTarget]] = [
        .leftHalf:  [.leftHalf, .leftThird, .leftTwoThirds],
        .rightHalf: [.rightHalf, .rightThird, .rightTwoThirds],
    ]

    // MARK: snap

    func snap(_ target: SnapTarget, animated: Bool = true, cycleSize: Bool = false) {
        guard let window = focusedWindow() else {
            print("[Glide][snap] no focused window")
            return
        }
        let resolved = cycleSize ? cycledTarget(target, window: window) : target
        if !cycleSize { resetCycle() }
        snap(resolved, window: window, animated: animated)
    }

    private func cycledTarget(_ requested: SnapTarget, window: AXUIElement) -> SnapTarget {
        guard let sequence = Self.cycleSequences[requested] else {
            resetCycle()
            return requested
        }
        let now = CACurrentMediaTime()
        let sameWindow = cycleWindow.map { CFEqual($0, window) } ?? false
        if sameWindow, cycleBase == requested, now - cycleTime < cycleTimeout {
            cycleIndex = (cycleIndex + 1) % sequence.count
        } else {
            cycleIndex = 0
        }
        cycleWindow = window
        cycleBase = requested
        cycleTime = now
        return sequence[cycleIndex]
    }

    private func resetCycle() {
        cycleWindow = nil
        cycleBase = nil
        cycleIndex = 0
    }

    func snap(_ target: SnapTarget, window: AXUIElement, animated: Bool = true) {
        let frame = currentCocoaFrame(of: window)
        guard let screen = frame.flatMap(screen(containing:)) ?? NSScreen.main else {
            print("[Glide][snap] no screen for window")
            return
        }
        apply(target, window: window, from: frame, screen: screen, animated: animated)
    }

    /// Snaps onto whichever screen contains `point` (the cursor), so dragging a
    /// window toward another display's edge snaps it there rather than on its
    /// origin screen.
    func snap(_ target: SnapTarget, window: AXUIElement,
              onScreenContaining point: CGPoint, animated: Bool = true) {
        let frame = currentCocoaFrame(of: window)
        let screen = NSScreen.screens.first { $0.frame.contains(point) }
            ?? frame.flatMap(screen(containing:)) ?? NSScreen.main
        guard let screen else { return }
        apply(target, window: window, from: frame, screen: screen, animated: animated)
    }

    private func apply(_ target: SnapTarget, window: AXUIElement, from startRect: CGRect?,
                       screen: NSScreen, animated: Bool) {
        let endRect = target.rect(in: screen.visibleFrame)
        if animated, let startRect {
            animateFrame(window: window, from: startRect, to: endRect)
        } else {
            setFrameNow(window, to: endRect)
        }
        // Subtle Force Touch trackpad click on snap. Silently ignored on devices
        // without a haptic trackpad.
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    // MARK: multi-display

    /// Throws the focused window to the next/previous screen.
    func moveToAdjacentDisplay(forward: Bool, animated: Bool = true) {
        guard let window = focusedWindow() else {
            print("[Glide][display] no focused window")
            return
        }
        moveToAdjacentDisplay(forward: forward, window: window, animated: animated)
    }

    /// Moves a specific window to the next/previous screen, preserving its
    /// position and size proportionally relative to the screen's visible area.
    func moveToAdjacentDisplay(forward: Bool, window: AXUIElement, animated: Bool = true) {
        let screens = NSScreen.screens
        guard screens.count > 1 else {
            print("[Glide][display] only one screen")
            return
        }
        guard let windowCocoa = currentCocoaFrame(of: window),
              let currentScreen = screen(containing: windowCocoa) ?? NSScreen.main,
              let currentIdx = screens.firstIndex(of: currentScreen) else { return }

        let delta = forward ? 1 : -1
        let nextScreen = screens[(currentIdx + delta + screens.count) % screens.count]
        let cur = currentScreen.visibleFrame
        let next = nextScreen.visibleFrame

        // Map the window's relative placement from the old screen to the new one.
        let relX = (windowCocoa.minX - cur.minX) / cur.width
        let relY = (windowCocoa.minY - cur.minY) / cur.height
        let relW = windowCocoa.width / cur.width
        let relH = windowCocoa.height / cur.height
        let target = CGRect(
            x: next.minX + relX * next.width,
            y: next.minY + relY * next.height,
            width: relW * next.width,
            height: relH * next.height
        )

        if animated {
            animateFrame(window: window, from: windowCocoa, to: target)
        } else {
            setFrameNow(window, to: target)
        }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    // MARK: animation

    private func animateFrame(window: AXUIElement, from start: CGRect, to end: CGRect) {
        // Cancel any in-flight animation. A different window is pinned to its
        // target so it isn't left half-way; the same window just re-targets
        // from wherever it is now (`start`).
        if let previous = animWindow, !CFEqual(previous, window) {
            setFrame(previous, to: animEnd)
        }
        stopAnimation()

        // On macOS CADisplayLink is created via NSScreen — not the iOS-style
        // CADisplayLink(target:selector:) initializer (which is unavailable here).
        // Use the window's own screen so the animation runs at its refresh rate
        // (a 120 Hz built-in panel next to a 60 Hz external, say).
        let startCenter = CGPoint(x: start.midX, y: start.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(startCenter) } ?? NSScreen.main
        guard let link = screen?.displayLink(
            target: self,
            selector: #selector(tickAnimation(_:))
        ) else {
            setFrameNow(window, to: end)
            return
        }

        animWindow = window
        animStart = start
        animEnd = end
        animStartTime = CACurrentMediaTime()
        animLastWritten = nil
        animEnhancedUIApp = disableEnhancedUI(for: window)
        // Glide is a background agent, so App Nap may coalesce its timers and
        // display-link callbacks. Opt out for the few frames of the animation.
        animActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical],
            reason: "Window snap animation"
        )
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopAnimation() {
        displayLink?.invalidate()
        displayLink = nil
        animWindow = nil
        animLastWritten = nil
        restoreEnhancedUI(animEnhancedUIApp)
        animEnhancedUIApp = nil
        if let animActivity {
            ProcessInfo.processInfo.endActivity(animActivity)
            self.animActivity = nil
        }
    }

    @objc private func tickAnimation(_ link: CADisplayLink) {
        guard let window = animWindow else {
            stopAnimation()
            return
        }
        // Interpolate to targetTimestamp (when this frame is actually shown on
        // screen) rather than timestamp (when the callback ran). This cancels
        // the callback→display latency and makes motion land where the eye
        // expects it.
        let elapsed = link.targetTimestamp - animStartTime
        let t = min(max(elapsed / animDuration, 0), 1.0)
        let eased = Self.easeOutCubic(t)

        let current = CGRect(
            x: animStart.minX + (animEnd.minX - animStart.minX) * eased,
            y: animStart.minY + (animEnd.minY - animStart.minY) * eased,
            width: animStart.width + (animEnd.width - animStart.width) * eased,
            height: animStart.height + (animEnd.height - animStart.height) * eased
        )
        if t >= 1.0 {
            // Pin to exact target — floating point + AX rounding can leave a 1-px gap.
            setFrame(window, to: animEnd)
            stopAnimation()
            return
        }

        let writeStart = CACurrentMediaTime()
        animLastWritten = setFrame(window, to: current, previous: animLastWritten)
        if CACurrentMediaTime() - writeStart > slowFrameLimit {
            // The app can't keep up with per-frame updates; finish in one step
            // rather than stutter through the rest of the animation.
            setFrame(window, to: animEnd)
            stopAnimation()
        }
    }

    private static func easeOutCubic(_ t: Double) -> Double {
        let f = t - 1
        return f * f * f + 1
    }

    // MARK: window resolution

    /// Called on every click and scroll-begin anywhere on screen, so the common
    /// "not on a title bar" case is ruled out via the WindowServer first: AX
    /// hit-testing is a synchronous round-trip into the app under the cursor
    /// and would add latency to that app's own clicks and scrolls.
    func titleBarWindow(at cocoaPoint: CGPoint) -> AXUIElement? {
        let axPoint = cocoaToAX(cocoaPoint)
        guard mayBeTitleBar(at: axPoint),
              let window = window(at: axPoint),
              let frame = axFrame(of: window) else { return nil }
        let titleBar = CGRect(x: frame.minX, y: frame.minY,
                              width: frame.width, height: titleBarHeight)
        return titleBar.contains(axPoint) ? window : nil
    }

    /// Is `axPoint` in the top `titleBarHeight` of the front-most window under
    /// it? Uses window bounds and layer only — those need no Screen Recording
    /// permission (window *names* would, and we never read them).
    private func mayBeTitleBar(at axPoint: CGPoint) -> Bool {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else {
            return true  // can't tell — let the AX check decide
        }
        // The list is ordered front to back, so the first hit is the window
        // actually under the cursor.
        for info in list {
            guard let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  bounds.contains(axPoint),
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { continue }
            // Dock, menu bar, open menus, overlays: never a draggable title bar.
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            guard layer < Int(CGWindowLevelForKey(.dockWindow)) else { return false }
            return axPoint.y - bounds.minY <= titleBarHeight
        }
        return false
    }

    // MARK: AX helpers

    private func focusedWindow() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        guard let appRef = copyAttribute(systemWide, kAXFocusedApplicationAttribute) else { return nil }
        let app = appRef as! AXUIElement
        guard let windowRef = copyAttribute(app, kAXFocusedWindowAttribute) else { return nil }
        return (windowRef as! AXUIElement)
    }

    private func window(at axPoint: CGPoint) -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(
            systemWide, Float(axPoint.x), Float(axPoint.y), &element
        )
        guard result == .success, let element else { return nil }
        return walkUpToWindow(element)
    }

    private func walkUpToWindow(_ element: AXUIElement) -> AXUIElement? {
        // Most elements expose their window directly — one round-trip instead
        // of one per parent level.
        if let windowRef = copyAttribute(element, kAXWindowAttribute) {
            return (windowRef as! AXUIElement)
        }
        var current = element
        for _ in 0..<20 {
            if let roleRef = copyAttribute(current, kAXRoleAttribute),
               let role = roleRef as? String,
               role == kAXWindowRole as String {
                return current
            }
            guard let parentRef = copyAttribute(current, kAXParentAttribute) else { return nil }
            current = parentRef as! AXUIElement
        }
        return nil
    }

    private func axFrame(of window: AXUIElement) -> CGRect? {
        guard let posRef = copyAttribute(window, kAXPositionAttribute),
              let sizeRef = copyAttribute(window, kAXSizeAttribute) else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &origin)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }

    private func currentCocoaFrame(of window: AXUIElement) -> CGRect? {
        guard let axRect = axFrame(of: window),
              let primary = NSScreen.screens.first else { return nil }
        let cocoaY = primary.frame.maxY - axRect.maxY
        return CGRect(x: axRect.minX, y: cocoaY, width: axRect.width, height: axRect.height)
    }

    private func copyAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var ref: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &ref)
        return result == .success ? ref : nil
    }

    private func cocoaToAX(_ cocoaPoint: CGPoint) -> CGPoint {
        guard let primary = NSScreen.screens.first else { return cocoaPoint }
        return CGPoint(x: cocoaPoint.x, y: primary.frame.maxY - cocoaPoint.y)
    }

    private func screen(containing cocoaFrame: CGRect) -> NSScreen? {
        let center = CGPoint(x: cocoaFrame.midX, y: cocoaFrame.midY)
        return NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? NSScreen.main
    }

    /// One-shot frame change (no animation), with enhanced UI switched off
    /// around it.
    private func setFrameNow(_ window: AXUIElement, to cocoaRect: CGRect) {
        let app = disableEnhancedUI(for: window)
        setFrame(window, to: cocoaRect)
        restoreEnhancedUI(app)
    }

    /// Writes the frame via AX and returns it in AX coordinates, rounded to
    /// whole points. With `previous` (an earlier return value), attributes
    /// that haven't visibly changed are skipped: each write is a synchronous
    /// round-trip to the target app, and a size write also makes it re-layout.
    @discardableResult
    private func setFrame(_ window: AXUIElement, to cocoaRect: CGRect,
                          previous: CGRect? = nil) -> CGRect? {
        guard let primary = NSScreen.screens.first else { return nil }
        let axOriginY = primary.frame.maxY - cocoaRect.maxY
        var origin = CGPoint(x: cocoaRect.minX, y: axOriginY)
        var size = cocoaRect.size
        let written = CGRect(x: origin.x.rounded(), y: origin.y.rounded(),
                             width: size.width.rounded(), height: size.height.rounded())
        // Size before position: when a window must both shrink and move, sizing
        // it down first keeps it within screen bounds for the position step.
        if written.size != previous?.size, let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
        if written.origin != previous?.origin, let posValue = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        }
        return written
    }

    // MARK: enhanced user interface

    // Chromium/Electron apps (and every app while VoiceOver runs) switch on
    // AXEnhancedUserInterface, which makes them animate each AX resize
    // themselves — slow, and it fights our animation. Turn it off while we move
    // the window and back on afterwards (the same trick Rectangle uses).
    private static let enhancedUIAttribute = "AXEnhancedUserInterface" as CFString

    /// Returns the app element whose flag was switched off, or nil if it was
    /// already off.
    private func disableEnhancedUI(for window: AXUIElement) -> AXUIElement? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success else { return nil }
        let app = AXUIElementCreateApplication(pid)
        guard let ref = copyAttribute(app, Self.enhancedUIAttribute as String),
              (ref as? Bool) == true else { return nil }
        AXUIElementSetAttributeValue(app, Self.enhancedUIAttribute, kCFBooleanFalse)
        return app
    }

    private func restoreEnhancedUI(_ app: AXUIElement?) {
        guard let app else { return }
        AXUIElementSetAttributeValue(app, Self.enhancedUIAttribute, kCFBooleanTrue)
    }
}
