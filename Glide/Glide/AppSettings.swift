//
//  AppSettings.swift
//  Glide
//

import Foundation

@Observable
final class AppSettings {
    var reverseScrolling: Bool {
        didSet { Self.defaults.set(reverseScrolling, forKey: Self.reverseScrollingKey) }
    }

    var animateSnap: Bool {
        didSet { Self.defaults.set(animateSnap, forKey: Self.animateSnapKey) }
    }

    init() {
        reverseScrolling = Self.defaults.bool(forKey: Self.reverseScrollingKey)
        // Default to true; user can disable in Preferences if it feels janky.
        animateSnap = Self.defaults.object(forKey: Self.animateSnapKey) as? Bool ?? true
    }

    private static let defaults = UserDefaults.standard
    private static let reverseScrollingKey = "reverseScrolling"
    private static let animateSnapKey = "animateSnap"
}
