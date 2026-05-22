//
//  WindowManager.swift
//  Glide
//

import AppKit
import ApplicationServices
import QuartzCore

enum SnapTarget: Equatable {
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

    // MARK: snap

    func snap(_ target: SnapTarget, animated: Bool = true) {
        guard let window = focusedWindow() else {
            print("[Glide][snap] no focused window")
            return
        }
        snap(target, window: window, animated: animated)
    }

    func snap(_ target: SnapTarget, window: AXUIElement, animated: Bool = true) {
        guard let screen = screenContaining(window: window) else {
            print("[Glide][snap] no screen for window")
            return
        }
        let endRect = target.rect(in: screen.visibleFrame)

        if animated, let startRect = currentCocoaFrame(of: window) {
            animateFrame(window: window, from: startRect, to: endRect)
        } else {
            setFrame(window, to: endRect)
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
        guard let currentScreen = screenContaining(window: window),
              let currentIdx = screens.firstIndex(of: currentScreen),
              let windowCocoa = currentCocoaFrame(of: window) else { return }

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
            setFrame(window, to: target)
        }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    // MARK: animation

    private func animateFrame(window: AXUIElement, from start: CGRect, to end: CGRect) {
        // Cancel any in-flight animation.
        displayLink?.invalidate()
        displayLink = nil

        animWindow = window
        animStart = start
        animEnd = end
        animStartTime = CACurrentMediaTime()

        // On macOS CADisplayLink is created via NSScreen — not the iOS-style
        // CADisplayLink(target:selector:) initializer (which is unavailable here).
        guard let link = NSScreen.main?.displayLink(
            target: self,
            selector: #selector(tickAnimation(_:))
        ) else {
            setFrame(window, to: end)
            animWindow = nil
            return
        }
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func tickAnimation(_ link: CADisplayLink) {
        guard let window = animWindow else {
            link.invalidate()
            displayLink = nil
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
        setFrame(window, to: current)

        if t >= 1.0 {
            // Pin to exact target — floating point + AX rounding can leave a 1-px gap.
            setFrame(window, to: animEnd)
            link.invalidate()
            displayLink = nil
            animWindow = nil
        }
    }

    private static func easeOutCubic(_ t: Double) -> Double {
        let f = t - 1
        return f * f * f + 1
    }

    // MARK: window resolution

    func titleBarWindow(at cocoaPoint: CGPoint) -> AXUIElement? {
        let axPoint = cocoaToAX(cocoaPoint)
        guard let window = window(at: axPoint),
              let frame = axFrame(of: window) else { return nil }
        let titleBar = CGRect(x: frame.minX, y: frame.minY,
                              width: frame.width, height: titleBarHeight)
        return titleBar.contains(axPoint) ? window : nil
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

    private func screenContaining(window: AXUIElement) -> NSScreen? {
        guard let primary = NSScreen.screens.first,
              let axRect = axFrame(of: window) else {
            return NSScreen.main
        }
        let cocoaY = primary.frame.maxY - axRect.maxY
        let cocoaCenter = CGPoint(x: axRect.midX, y: cocoaY + axRect.height / 2)
        return NSScreen.screens.first(where: { $0.frame.contains(cocoaCenter) }) ?? NSScreen.main
    }

    private func setFrame(_ window: AXUIElement, to cocoaRect: CGRect) {
        guard let primary = NSScreen.screens.first else { return }
        let axOriginY = primary.frame.maxY - cocoaRect.maxY
        var origin = CGPoint(x: cocoaRect.minX, y: axOriginY)
        var size = cocoaRect.size
        // Size before position: when a window must both shrink and move, sizing
        // it down first keeps it within screen bounds for the position step.
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
        if let posValue = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        }
    }
}
