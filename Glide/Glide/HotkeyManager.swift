//
//  HotkeyManager.swift
//  Glide
//

import AppKit
import Carbon.HIToolbox

enum HotkeyAction {
    case snap(SnapTarget)
    case moveToNextDisplay
    case moveToPreviousDisplay
    case cycleWindow
    case saveLayout
    case restoreLayout
    case hideOthers
    case hideAll
}

/// Registers the user's bindings as Carbon hotkeys. Unlike an NSEvent global
/// monitor, `RegisterEventHotKey` *consumes* the key event, so a remapped combo
/// won't also fire in the focused app. Re-registers whenever the store changes.
final class HotkeyManager {
    var onAction: ((HotkeyAction) -> Void)?
    /// Fired with a layout's id when its shortcut is pressed.
    var onLayoutHotkey: ((UUID) -> Void)?
    /// Supplies the current layout shortcuts to register. Set by AppDelegate.
    var layoutShortcuts: () -> [(id: UUID, shortcut: Shortcut)] = { [] }

    private let store: ShortcutStore
    private var handlerRef: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var actionByNumber: [UInt32: HotkeyActionID] = [:]
    private var layoutByNumber: [UInt32: UUID] = [:]

    init(store: ShortcutStore) {
        self.store = store
    }

    func start() {
        installHandler()
        reload()
        store.onChange = { [weak self] in self?.reload() }
    }

    /// Re-register everything (e.g. after layout shortcuts change).
    func refresh() {
        reload()
    }

    func stop() {
        unregisterAll()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        store.onChange = nil
    }

    fileprivate func handle(number: UInt32) {
        if let id = actionByNumber[number] {
            onAction?(id.action)
        } else if let layoutID = layoutByNumber[number] {
            onLayoutHotkey?(layoutID)
        }
    }

    // MARK: registration

    private func installHandler() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), hotKeyCallback, 1, &spec, selfPtr, &handlerRef)
    }

    private func reload() {
        unregisterAll()
        guard !store.suspended else {
            store.failedRegistrations = []
            print("[Glide][hotkey] suspended — 0 hotkeys")
            return
        }
        var failures: Set<HotkeyActionID> = []
        var number: UInt32 = 1
        for (id, shortcut) in store.bindings {
            let hkID = EventHotKeyID(signature: glideHotKeySignature, id: number)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(shortcut.keyCode),
                shortcut.carbonModifiers,
                hkID,
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if status == noErr, let ref {
                hotKeyRefs.append(ref)
                actionByNumber[number] = id
                number += 1
            } else {
                failures.insert(id)
                print("[Glide][hotkey] register failed for \(id) status=\(status)")
            }
        }
        store.failedRegistrations = failures

        for (layoutID, shortcut) in layoutShortcuts() {
            let hkID = EventHotKeyID(signature: glideHotKeySignature, id: number)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(shortcut.keyCode), shortcut.carbonModifiers,
                hkID, GetApplicationEventTarget(), 0, &ref
            )
            if status == noErr, let ref {
                hotKeyRefs.append(ref)
                layoutByNumber[number] = layoutID
                number += 1
            } else {
                print("[Glide][hotkey] register failed for layout \(layoutID) status=\(status)")
            }
        }
        print("[Glide][hotkey] registered \(hotKeyRefs.count) hotkeys")
    }

    private func unregisterAll() {
        for ref in hotKeyRefs { UnregisterEventHotKey(ref) }
        hotKeyRefs.removeAll()
        actionByNumber.removeAll()
        layoutByNumber.removeAll()
    }
}

// C callback: routes the fired hotkey back to the HotkeyManager carried in userData.
private let hotKeyCallback: EventHandlerUPP = { _, eventRef, userData in
    guard let eventRef, let userData else { return OSStatus(eventNotHandledErr) }
    var hkID = EventHotKeyID()
    let status = GetEventParameter(
        eventRef,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hkID
    )
    guard status == noErr else { return status }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    manager.handle(number: hkID.id)
    return noErr
}
