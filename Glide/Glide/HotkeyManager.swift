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

    private let store: ShortcutStore
    private var handlerRef: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var actionByNumber: [UInt32: HotkeyActionID] = [:]

    init(store: ShortcutStore) {
        self.store = store
    }

    func start() {
        installHandler()
        reload()
        store.onChange = { [weak self] in self?.reload() }
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
        guard let id = actionByNumber[number] else { return }
        onAction?(id.action)
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
        print("[Glide][hotkey] registered \(hotKeyRefs.count) hotkeys")
    }

    private func unregisterAll() {
        for ref in hotKeyRefs { UnregisterEventHotKey(ref) }
        hotKeyRefs.removeAll()
        actionByNumber.removeAll()
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
