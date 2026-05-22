//
//  PreferencesView.swift
//  Glide
//

import SwiftUI
import ServiceManagement

enum RecordTarget: Equatable {
    case action(HotkeyActionID)
    case layout(UUID)
}

struct PreferencesView: View {
    @Bindable var settings: AppSettings
    let shortcuts: ShortcutStore
    let layoutManager: LayoutManager
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
    @State private var recordingTarget: RecordTarget?
    @State private var recordMonitor: Any?
    @State private var note: String?
    @State private var renamingLayout: WindowLayout?
    @State private var renameText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Glide Preferences")
                .font(.title2)
                .padding(.bottom, 4)

            GroupBox(label: Text("General").font(.headline)) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Launch Glide at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, enabled in
                            updateLoginItem(enabled: enabled)
                        }
                    Toggle("Reverse vertical scrolling", isOn: $settings.reverseScrolling)
                    Toggle("Animate window movement", isOn: $settings.animateSnap)
                    Toggle("Snap when dragging to screen edges", isOn: $settings.edgeSnapEnabled)
                    Toggle("Cycle sizes when repeating a snap shortcut", isOn: $settings.sizeCycleEnabled)
                }
                .padding(8)
            }

            GroupBox(label: keyboardHeader) {
                VStack(alignment: .leading, spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(HotkeyActionID.allCases, id: \.self) { id in
                                shortcutRow(id)
                            }
                        }
                        .padding(8)
                    }
                    .frame(height: 280)
                    if let note {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.bottom, 6)
                    }
                }
            }

            GroupBox(label: Text("Layouts").font(.headline)) {
                VStack(alignment: .leading, spacing: 4) {
                    if layoutManager.namedLayouts.isEmpty {
                        Text("No saved layouts yet. Menu bar → Layouts → Save Current Layout as…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(layoutManager.namedLayouts) { layout in
                                    layoutRow(layout)
                                }
                            }
                        }
                        .frame(maxHeight: 140)
                    }
                }
                .padding(8)
            }

            GroupBox(label: Text("Trackpad").font(.headline)) {
                VStack(alignment: .leading, spacing: 4) {
                    shortcut("Snap window",      "2-finger swipe on title bar")
                    shortcut("Move to display",  "⌘ + swipe on title bar")
                }
                .padding(8)
            }

            HStack {
                Text("Version \(versionString)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Spacer()
            }
        }
        .padding(20)
        .frame(width: 420)
        .onDisappear { stopRecording() }
        .alert("Rename Layout", isPresented: Binding(
            get: { renamingLayout != nil },
            set: { if !$0 { renamingLayout = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renamingLayout = nil }
            Button("Save") {
                if let layout = renamingLayout { layoutManager.rename(id: layout.id, to: renameText) }
                renamingLayout = nil
            }
        }
    }

    private var keyboardHeader: some View {
        HStack {
            Text("Keyboard Shortcuts").font(.headline)
            Spacer()
            Button("Reset to Defaults") {
                stopRecording()
                shortcuts.resetToDefaults()
                note = nil
            }
            .font(.caption)
        }
    }

    private func shortcutRow(_ id: HotkeyActionID) -> some View {
        let isRecording = recordingTarget == .action(id)
        let current = shortcuts.shortcut(for: id)
        return HStack {
            Text(id.title)
            Spacer()
            if shortcuts.failedRegistrations.contains(id) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .help("This combination is reserved by macOS and couldn't be registered. Pick another.")
            }
            Button(action: { isRecording ? stopRecording() : startRecording(.action(id)) }) {
                Text(isRecording ? "Press keys…" : (current?.displayString ?? "Unbound"))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(isRecording ? Color.accentColor : (current == nil ? .secondary : .primary))
                    .frame(minWidth: 70)
            }
            .buttonStyle(.bordered)
            Button {
                shortcuts.clear(id)
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .opacity(current == nil ? 0 : 1)
            .disabled(current == nil)
        }
    }

    private func layoutRow(_ layout: WindowLayout) -> some View {
        let isRecording = recordingTarget == .layout(layout.id)
        return HStack {
            Text(layout.name).lineLimit(1)
            Spacer()
            Button(action: { isRecording ? stopRecording() : startRecording(.layout(layout.id)) }) {
                Text(isRecording ? "Press keys…" : (layout.shortcut?.displayString ?? "No shortcut"))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(isRecording ? Color.accentColor : (layout.shortcut == nil ? .secondary : .primary))
                    .frame(minWidth: 70)
            }
            .buttonStyle(.bordered)
            Button { layoutManager.setShortcut(nil, for: layout.id) } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless).foregroundStyle(.secondary)
            .opacity(layout.shortcut == nil ? 0 : 1)
            .disabled(layout.shortcut == nil)
            Button { renameText = layout.name; renamingLayout = layout } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless).foregroundStyle(.secondary)
            Button { layoutManager.delete(id: layout.id) } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless).foregroundStyle(.secondary)
        }
    }

    // MARK: shortcut recording

    private func startRecording(_ target: RecordTarget) {
        stopRecording()
        // Suspend live hotkeys so pressing an already-bound combo gets captured
        // here instead of firing its system-wide action.
        shortcuts.suspend()
        recordingTarget = target
        note = "Press a combo (Esc to cancel)"
        recordMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            handleRecording(event)
            return nil  // swallow so the keystroke doesn't leak into the UI / beep
        }
    }

    private func handleRecording(_ event: NSEvent) {
        guard let target = recordingTarget else { return }
        let masked = event.modifierFlags.intersection([.control, .option, .shift, .command])

        if Int(event.keyCode) == 53 && masked.isEmpty {  // Escape
            stopRecording()
            note = nil
            return
        }
        // A modifier-less (or shift-only) global hotkey would swallow normal
        // typing, so require at least one of ⌃⌥⌘.
        guard masked.contains(.control) || masked.contains(.option) || masked.contains(.command) else {
            note = "Use at least ⌃, ⌥, or ⌘"
            return
        }

        let shortcut = Shortcut(keyCode: event.keyCode, modifierFlags: masked.rawValue)
        switch target {
        case .action(let id):
            let stolen = shortcuts.assign(shortcut, to: id)
            stopRecording()  // resume() re-registers synchronously, so failures are known now
            if shortcuts.failedRegistrations.contains(id) {
                note = "\(shortcut.displayString) is reserved by macOS — \(id.title) won't trigger. Pick another."
            } else if let stolen {
                note = "\(shortcut.displayString) → \(id.title) (was \(stolen))"
            } else {
                note = "\(id.title) → \(shortcut.displayString)"
            }
        case .layout(let layoutID):
            let name = layoutManager.namedLayouts.first { $0.id == layoutID }?.name ?? "layout"
            let stolen = layoutManager.setShortcut(shortcut, for: layoutID)
            stopRecording()
            if let stolen {
                note = "\(shortcut.displayString) → \(name) (was \(stolen))"
            } else {
                note = "\(name) → \(shortcut.displayString)"
            }
        }
    }

    private func stopRecording() {
        let wasRecording = recordMonitor != nil
        if let recordMonitor {
            NSEvent.removeMonitor(recordMonitor)
            self.recordMonitor = nil
        }
        recordingTarget = nil
        if wasRecording {
            shortcuts.resume()  // re-registers with current bindings
            note = nil          // clear the stale "Recording…" hint on cancel
        }
    }

    private func shortcut(_ name: String, _ keys: String) -> some View {
        HStack {
            Text(name)
            Spacer()
            Text(keys)
                .foregroundStyle(.secondary)
                .font(.system(.body, design: .monospaced))
        }
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    private func updateLoginItem(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("[Glide][prefs] login item update failed: \(error)")
            // Roll back UI state on failure so toggle reflects truth
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
