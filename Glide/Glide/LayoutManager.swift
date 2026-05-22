//
//  LayoutManager.swift
//  Glide
//

import AppKit
import ApplicationServices

private struct WindowSnapshot: Codable {
    let bundleID: String
    let title: String
    let frame: CGRect  // raw AX coordinates (top-left origin)
}

/// Captures the position + size of every standard window and restores them
/// later. Matching on restore is best-effort: a window is identified by its
/// app bundle ID + title, so windows whose titles changed are skipped.
final class LayoutManager {
    private static let key = "savedLayout"

    var hasSavedLayout: Bool {
        UserDefaults.standard.data(forKey: Self.key) != nil
    }

    func saveLayout() {
        let snapshots = captureAll()
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
        print("[Glide][layout] saved \(snapshots.count) windows")
    }

    func restoreLayout() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let snapshots = try? JSONDecoder().decode([WindowSnapshot].self, from: data) else {
            print("[Glide][layout] no saved layout")
            return
        }
        applyLayout(snapshots)
    }

    // MARK: capture / apply

    private func captureAll() -> [WindowSnapshot] {
        var result: [WindowSnapshot] = []
        for app in regularApps() {
            guard let bundleID = app.bundleIdentifier else { continue }
            for window in windows(ofPID: app.processIdentifier) {
                guard let frame = axFrame(of: window) else { continue }
                result.append(WindowSnapshot(
                    bundleID: bundleID,
                    title: title(of: window),
                    frame: frame
                ))
            }
        }
        return result
    }

    private func applyLayout(_ snapshots: [WindowSnapshot]) {
        // Index live windows by (bundleID, title) for quick matching.
        var liveWindows: [String: [String: AXUIElement]] = [:]
        for app in regularApps() {
            guard let bundleID = app.bundleIdentifier else { continue }
            var byTitle: [String: AXUIElement] = [:]
            for window in windows(ofPID: app.processIdentifier) {
                byTitle[title(of: window)] = window
            }
            liveWindows[bundleID] = byTitle
        }

        var restored = 0
        for snapshot in snapshots {
            guard let window = liveWindows[snapshot.bundleID]?[snapshot.title] else { continue }
            setAXFrame(window, snapshot.frame)
            restored += 1
        }
        print("[Glide][layout] restored \(restored)/\(snapshots.count) windows")
    }

    // MARK: AX helpers

    private func regularApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
    }

    private func windows(ofPID pid: pid_t) -> [AXUIElement] {
        let axApp = AXUIElementCreateApplication(pid)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &ref) == .success,
              let windows = ref as? [AXUIElement] else { return [] }
        return windows
    }

    private func axFrame(of window: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success else {
            return nil
        }
        var origin = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &origin)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }

    private func setAXFrame(_ window: AXUIElement, _ frame: CGRect) {
        var origin = frame.origin
        var size = frame.size
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
        if let posValue = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        }
    }

    private func title(of window: AXUIElement) -> String {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &ref) == .success,
              let title = ref as? String else { return "" }
        return title
    }
}
