//
//  GlideApp.swift
//  Glide
//
//

import SwiftUI

@main
struct GlideApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // We don't actually want any window — the entire UI is the NSStatusItem
        // built in AppDelegate. App protocol requires at least one Scene, so we
        // declare a hidden Settings scene that never opens on its own.
        Settings { EmptyView() }
    }
}
