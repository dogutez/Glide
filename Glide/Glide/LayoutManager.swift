//
//  LayoutManager.swift
//  Glide
//

import AppKit
import ApplicationServices
import Observation

struct WindowSnapshot: Codable {
    let bundleID: String
    let title: String
    let frame: CGRect  // raw AX coordinates (top-left origin)
}

/// A named, restorable arrangement of windows, with an optional global shortcut.
/// Named `WindowLayout` (not `Layout`) to avoid colliding with SwiftUI.Layout.
struct WindowLayout: Codable, Identifiable {
    let id: UUID
    var name: String
    var snapshots: [WindowSnapshot]
    var shortcut: Shortcut?  // absent in old data decodes to nil
}

/// Captures the position + size of every standard window and restores them
/// later. Matching on restore is best-effort: a window is identified by its
/// app bundle ID + title, so windows whose titles changed are skipped.
@Observable
final class LayoutManager {
    private static let key = "savedLayout"
    private static let namedKey = "namedLayouts"

    /// Named layouts, newest last. Loaded once at init; mutations persist.
    private(set) var namedLayouts: [WindowLayout] = []

    /// Fired when the set of layout shortcuts changes, so HotkeyManager
    /// re-registers. NOT fired on rename (no shortcut change).
    @ObservationIgnored var shortcutsChanged: (() -> Void)?

    /// Clears any HotkeyActionID bound to a combo (returns its title) so a
    /// layout can steal it. Set by AppDelegate.
    @ObservationIgnored var actionConflictResolver: ((Shortcut) -> String?)?

    init() {
        namedLayouts = Self.loadNamed()
    }

    // MARK: quick slot (single, hotkey-friendly)

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

    // MARK: named layouts

    func saveCurrentAs(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let layout = WindowLayout(id: UUID(), name: trimmed, snapshots: captureAll(), shortcut: nil)
        namedLayouts.append(layout)
        persistNamed()
        print("[Glide][layout] saved named '\(trimmed)' (\(layout.snapshots.count) windows)")
    }

    func restore(id: UUID) {
        guard let layout = namedLayouts.first(where: { $0.id == id }) else { return }
        applyLayout(layout.snapshots)
    }

    func rename(id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = namedLayouts.firstIndex(where: { $0.id == id }) else { return }
        namedLayouts[index].name = trimmed
        persistNamed()
    }

    func delete(id: UUID) {
        let hadShortcut = namedLayouts.first { $0.id == id }?.shortcut != nil
        namedLayouts.removeAll { $0.id == id }
        persistNamed()
        if hadShortcut { shortcutsChanged?() }
    }

    /// Assigns (or clears, when nil) a layout's shortcut, stealing the combo
    /// from any other layout or action that holds it. Returns the displaced
    /// item's name for a "(was X)" note.
    @discardableResult
    func setShortcut(_ shortcut: Shortcut?, for id: UUID) -> String? {
        guard let index = namedLayouts.firstIndex(where: { $0.id == id }) else { return nil }
        var displaced: String?
        if let shortcut {
            for i in namedLayouts.indices where i != index && namedLayouts[i].shortcut == shortcut {
                displaced = namedLayouts[i].name
                namedLayouts[i].shortcut = nil
            }
            if let stolenAction = actionConflictResolver?(shortcut), displaced == nil {
                displaced = stolenAction
            }
        }
        namedLayouts[index].shortcut = shortcut
        persistNamed()
        shortcutsChanged?()
        return displaced
    }

    /// Clears whichever layout holds `shortcut` (returns its name). Lets an
    /// action steal a combo from a layout.
    func clearLayoutWithShortcut(_ shortcut: Shortcut) -> String? {
        guard let i = namedLayouts.firstIndex(where: { $0.shortcut == shortcut }) else { return nil }
        let name = namedLayouts[i].name
        namedLayouts[i].shortcut = nil
        persistNamed()
        shortcutsChanged?()
        return name
    }

    private struct NamedPayload: Codable {
        var v: Int
        var layouts: [WindowLayout]
    }

    private func persistNamed() {
        let payload = NamedPayload(v: 1, layouts: namedLayouts)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: Self.namedKey)
    }

    private static func loadNamed() -> [WindowLayout] {
        guard let data = UserDefaults.standard.data(forKey: namedKey),
              let payload = try? JSONDecoder().decode(NamedPayload.self, from: data) else { return [] }
        return payload.layouts
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
