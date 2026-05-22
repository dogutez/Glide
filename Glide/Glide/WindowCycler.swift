//
//  WindowCycler.swift
//  Glide
//

import AppKit
import ApplicationServices

/// Cycles focus through every standard window of every regular app — a
/// window-level alternative to the app-level Cmd-Tab. No previews (that would
/// need Screen Recording); it simply raises the next window in a stable order.
final class WindowCycler {

    func cycleForward() {
        let windows = allWindows()
        guard !windows.isEmpty else {
            print("[Glide][cycle] no windows")
            return
        }

        let nextIndex: Int
        if let current = focusedWindow(),
           let idx = windows.firstIndex(where: { CFEqual($0.window, current) }) {
            nextIndex = (idx + 1) % windows.count
        } else {
            nextIndex = 0
        }

        let target = windows[nextIndex]
        target.app.activate()
        AXUIElementPerformAction(target.window, kAXRaiseAction as CFString)
        print("[Glide][cycle] raised window \(nextIndex + 1)/\(windows.count)")
    }

    // MARK: helpers

    private func allWindows() -> [(app: NSRunningApplication, window: AXUIElement)] {
        var result: [(NSRunningApplication, AXUIElement)] = []
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }

        for app in apps {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            var windowsRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                  let windows = windowsRef as? [AXUIElement] else { continue }
            for window in windows where !isMinimized(window) {
                result.append((app, window))
            }
        }
        return result
    }

    private func focusedWindow() -> AXUIElement? {
        guard let front = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(front.processIdentifier)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &ref) == .success else {
            return nil
        }
        return (ref as! AXUIElement)
    }

    private func isMinimized(_ window: AXUIElement) -> Bool {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &ref) == .success,
              let minimized = ref as? Bool else { return false }
        return minimized
    }
}
