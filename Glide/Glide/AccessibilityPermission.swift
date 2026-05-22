//
//  AccessibilityPermission.swift
//  Glide
//

import AppKit
import ApplicationServices

@Observable
final class AccessibilityPermission {
    private(set) var isTrusted: Bool

    init() {
        let trusted = AXIsProcessTrusted()
        self.isTrusted = trusted
        Self.log(label: "init", trusted: trusted)
        // Notification observer for didBecomeActive is temporarily disabled —
        // suspected of cascading refresh() calls that hang main thread.
    }

    func refresh() {
        let trusted = AXIsProcessTrusted()
        if trusted != isTrusted {
            isTrusted = trusted
            Self.log(label: "refresh", trusted: trusted)
        }
    }

    func requestPrompt() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        isTrusted = trusted
        Self.log(label: "requestPrompt", trusted: trusted)
    }

    func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private static func log(label: String, trusted: Bool) {
        print("[Glide][\(label)] bundlePath=\(Bundle.main.bundlePath) trusted=\(trusted)")
    }
}
