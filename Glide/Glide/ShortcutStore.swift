//
//  ShortcutStore.swift
//  Glide
//

import Foundation
import Observation

/// Source of truth for keyboard-shortcut bindings. `HotkeyManager` reads it and
/// re-registers on `onChange`; `PreferencesView` edits it. Absence of a key
/// means the action is intentionally unbound.
@Observable
final class ShortcutStore {
    private(set) var bindings: [HotkeyActionID: Shortcut]

    /// Fired after any mutation so HotkeyManager can re-register.
    @ObservationIgnored var onChange: (() -> Void)?

    /// While true, HotkeyManager unregisters everything. Used during recording
    /// so an existing combo gets captured by the recorder instead of firing its
    /// (system-wide) Carbon hotkey.
    @ObservationIgnored private(set) var suspended = false

    /// Actions whose combo macOS refused to register (reserved system shortcuts
    /// like ⌘Space). Written by HotkeyManager; read by the UI to flag them.
    var failedRegistrations: Set<HotkeyActionID> = []

    /// Clears any layout holding a combo (returns its name) so an action can
    /// steal it. Set by AppDelegate.
    @ObservationIgnored var externalConflictResolver: ((Shortcut) -> String?)?

    init() {
        bindings = Self.load() ?? HotkeyActionID.defaultBindings
    }

    func suspend() {
        suspended = true
        onChange?()
    }

    func resume() {
        suspended = false
        onChange?()
    }

    func shortcut(for id: HotkeyActionID) -> Shortcut? { bindings[id] }

    /// Assigns `shortcut` to `id`, stealing the combo from any other action or
    /// layout that holds it. Returns the displaced item's display name for a
    /// "(was X)" note.
    @discardableResult
    func assign(_ shortcut: Shortcut, to id: HotkeyActionID) -> String? {
        var displaced: String?
        for (other, existing) in bindings where other != id && existing == shortcut {
            bindings[other] = nil
            displaced = other.title
        }
        bindings[id] = shortcut
        if let stolenLayout = externalConflictResolver?(shortcut), displaced == nil {
            displaced = stolenLayout
        }
        save()
        onChange?()
        return displaced
    }

    /// Clears whichever action holds `shortcut` (returns its title). Lets a
    /// layout steal a combo from an action.
    func clearActionWithShortcut(_ shortcut: Shortcut) -> String? {
        guard let entry = bindings.first(where: { $0.value == shortcut }) else { return nil }
        bindings[entry.key] = nil
        save()
        onChange?()
        return entry.key.title
    }

    func clear(_ id: HotkeyActionID) {
        guard bindings[id] != nil else { return }
        bindings[id] = nil
        save()
        onChange?()
    }

    func resetToDefaults() {
        bindings = HotkeyActionID.defaultBindings
        save()
        onChange?()
    }

    // MARK: persistence

    private static let key = "shortcutBindings"

    private struct Payload: Codable {
        var v: Int
        var bindings: [String: Shortcut]
    }

    private func save() {
        let map = Dictionary(uniqueKeysWithValues: bindings.map { ($0.key.rawValue, $0.value) })
        let payload = Payload(v: 1, bindings: map)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }

    private static func load() -> [HotkeyActionID: Shortcut]? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        var result: [HotkeyActionID: Shortcut] = [:]
        for (raw, shortcut) in payload.bindings {
            if let id = HotkeyActionID(rawValue: raw) { result[id] = shortcut }
        }
        return result
    }
}
