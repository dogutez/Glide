//
//  GestureMonitor.swift
//  Glide
//

import AppKit
import ApplicationServices

final class GestureMonitor {
    var onSwipe: ((SnapTarget, AXUIElement) -> Void)?
    var onMoveToDisplay: ((_ forward: Bool, _ window: AXUIElement) -> Void)?

    private let windows: WindowManager
    private let settings: AppSettings
    private var scrollMonitor: Any?

    private var accumulatingSwipe = false
    private var swipeWindow: AXUIElement?
    private var swipeCmdHeld = false
    private var swipeX: CGFloat = 0
    private var swipeY: CGFloat = 0

    private let swipeThreshold: CGFloat = 50

    init(windows: WindowManager, settings: AppSettings) {
        self.windows = windows
        self.settings = settings
    }

    func start() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScroll(event)
        }
        print("[Glide][gesture] scroll=\(scrollMonitor == nil ? "FAILED" : "started")")
    }

    func stop() {
        if let m = scrollMonitor {
            NSEvent.removeMonitor(m)
            scrollMonitor = nil
        }
    }

    private func handleScroll(_ event: NSEvent) {
        guard event.hasPreciseScrollingDeltas else { return }

        if event.phase.contains(.began) {
            let cursor = NSEvent.mouseLocation
            if let window = windows.titleBarWindow(at: cursor) {
                swipeWindow = window
                accumulatingSwipe = true
                swipeCmdHeld = event.modifierFlags.contains(.command)
                swipeX = 0
                swipeY = 0
                print("[Glide][swipe] began on titlebar cmd=\(swipeCmdHeld)")
            } else {
                accumulatingSwipe = false
                swipeWindow = nil
            }
            return
        }

        guard accumulatingSwipe else { return }

        if event.phase.contains(.changed) {
            swipeX += event.scrollingDeltaX
            swipeY += event.scrollingDeltaY
            return
        }

        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            defer {
                accumulatingSwipe = false
                swipeWindow = nil
                swipeCmdHeld = false
            }
            if event.phase.contains(.cancelled) {
                print("[Glide][swipe] cancelled")
                return
            }

            // Cmd held → move the window to the adjacent display instead of
            // snapping. Only horizontal swipes count; vertical Cmd-swipes are
            // ignored so an accidental tilt does nothing.
            if swipeCmdHeld {
                if abs(swipeX) > swipeThreshold, abs(swipeX) > abs(swipeY), let w = swipeWindow {
                    let forward = swipeX > 0
                    print("[Glide][swipe] cmd+swipe → move display forward=\(forward)")
                    onMoveToDisplay?(forward, w)
                }
                return
            }

            let target = decideSwipeTarget(dx: swipeX, dy: swipeY)
            let dxStr = String(format: "%+.1f", swipeX)
            let dyStr = String(format: "%+.1f", swipeY)
            let targetStr = target.map { String(describing: $0) } ?? "none"
            print("[Glide][swipe] ended dx=\(dxStr) dy=\(dyStr) target=\(targetStr)")
            if let t = target, let w = swipeWindow {
                onSwipe?(t, w)
            }
        }
    }

    private func decideSwipeTarget(dx: CGFloat, dy: CGFloat) -> SnapTarget? {
        let effDx = dx
        let effDy = settings.reverseScrolling ? -dy : dy
        let absX = abs(effDx)
        let absY = abs(effDy)
        let magnitude = hypot(absX, absY)

        guard magnitude > swipeThreshold else { return nil }

        let angle = atan2(absY, absX)
        let diagonalLow: CGFloat = .pi * 25 / 180
        let diagonalHigh: CGFloat = .pi * 65 / 180

        if angle > diagonalLow, angle < diagonalHigh {
            switch (effDx > 0, effDy > 0) {
            case (false, true):  return .topLeftQuadrant
            case (true,  true):  return .topRightQuadrant
            case (false, false): return .bottomLeftQuadrant
            case (true,  false): return .bottomRightQuadrant
            }
        }

        if angle <= diagonalLow {
            return effDx > 0 ? .rightHalf : .leftHalf
        }

        // Long swipe → full (up) or center (down); short swipe → halves.
        if effDy > 0 {
            return magnitude > swipeThreshold * 2.5 ? .full : .topHalf
        } else {
            return magnitude > swipeThreshold * 2.5 ? .center : .bottomHalf
        }
    }
}
