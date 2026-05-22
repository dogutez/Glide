//
//  Shortcut.swift
//  Glide
//

import AppKit
import Carbon.HIToolbox

/// FourCharCode 'GLDE' — tags our Carbon hotkeys so the event handler can
/// recognize them (though we register a dedicated handler, so any signature
/// would do).
let glideHotKeySignature = OSType(0x474C4445)

/// A user-assignable key combination. `modifierFlags` stores
/// `NSEvent.ModifierFlags.rawValue` masked to ⌃⌥⇧⌘.
struct Shortcut: Codable, Equatable {
    var keyCode: UInt16
    var modifierFlags: UInt

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifierFlags) }

    /// NSEvent modifier flags translated to the Carbon mask RegisterEventHotKey expects.
    var carbonModifiers: UInt32 {
        var mask: UInt32 = 0
        if flags.contains(.command) { mask |= UInt32(cmdKey) }
        if flags.contains(.option)  { mask |= UInt32(optionKey) }
        if flags.contains(.control) { mask |= UInt32(controlKey) }
        if flags.contains(.shift)   { mask |= UInt32(shiftKey) }
        return mask
    }

    var displayString: String {
        Shortcut.modifierGlyphs(flags) + Shortcut.keyLabel(for: keyCode)
    }

    static func modifierGlyphs(_ flags: NSEvent.ModifierFlags) -> String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option)  { s += "⌥" }
        if flags.contains(.shift)   { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s
    }

    static func keyLabel(for keyCode: UInt16) -> String {
        keyNames[Int(keyCode)] ?? "Key \(keyCode)"
    }
}

private let keyNames: [Int: String] = [
    kVK_Return: "⏎", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫", kVK_Escape: "⎋",
    kVK_ForwardDelete: "⌦", kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
    kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
    kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E",
    kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J",
    kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O",
    kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
    kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X", kVK_ANSI_Y: "Y",
    kVK_ANSI_Z: "Z",
    kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
    kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
    kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[",
    kVK_ANSI_RightBracket: "]", kVK_ANSI_Backslash: "\\", kVK_ANSI_Semicolon: ";",
    kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/",
    kVK_ANSI_Grave: "`",
]

/// Every action that can be bound to a shortcut. The raw value is the
/// persistence key, so don't rename cases without a migration.
enum HotkeyActionID: String, CaseIterable, Codable {
    case snapLeftHalf, snapRightHalf, snapTopHalf, snapBottomHalf
    case snapTopLeft, snapTopRight, snapBottomLeft, snapBottomRight
    case snapLeftThird, snapMiddleThird, snapRightThird
    case snapLeftTwoThirds, snapRightTwoThirds
    case snapCenter, snapFull
    case moveNextDisplay, movePreviousDisplay
    case cycleWindow, saveLayout, restoreLayout

    var action: HotkeyAction {
        switch self {
        case .snapLeftHalf:       return .snap(.leftHalf)
        case .snapRightHalf:      return .snap(.rightHalf)
        case .snapTopHalf:        return .snap(.topHalf)
        case .snapBottomHalf:     return .snap(.bottomHalf)
        case .snapTopLeft:        return .snap(.topLeftQuadrant)
        case .snapTopRight:       return .snap(.topRightQuadrant)
        case .snapBottomLeft:     return .snap(.bottomLeftQuadrant)
        case .snapBottomRight:    return .snap(.bottomRightQuadrant)
        case .snapLeftThird:      return .snap(.leftThird)
        case .snapMiddleThird:    return .snap(.middleThird)
        case .snapRightThird:     return .snap(.rightThird)
        case .snapLeftTwoThirds:  return .snap(.leftTwoThirds)
        case .snapRightTwoThirds: return .snap(.rightTwoThirds)
        case .snapCenter:         return .snap(.center)
        case .snapFull:           return .snap(.full)
        case .moveNextDisplay:    return .moveToNextDisplay
        case .movePreviousDisplay: return .moveToPreviousDisplay
        case .cycleWindow:        return .cycleWindow
        case .saveLayout:         return .saveLayout
        case .restoreLayout:      return .restoreLayout
        }
    }

    var title: String {
        switch self {
        case .snapLeftHalf:        return "Snap Left"
        case .snapRightHalf:       return "Snap Right"
        case .snapTopHalf:         return "Snap Top"
        case .snapBottomHalf:      return "Snap Bottom"
        case .snapTopLeft:         return "Top-Left Quadrant"
        case .snapTopRight:        return "Top-Right Quadrant"
        case .snapBottomLeft:      return "Bottom-Left Quadrant"
        case .snapBottomRight:     return "Bottom-Right Quadrant"
        case .snapLeftThird:       return "Left Third"
        case .snapMiddleThird:     return "Middle Third"
        case .snapRightThird:      return "Right Third"
        case .snapLeftTwoThirds:   return "Left Two-Thirds"
        case .snapRightTwoThirds:  return "Right Two-Thirds"
        case .snapCenter:          return "Center"
        case .snapFull:            return "Fill Screen"
        case .moveNextDisplay:     return "Move to Next Display"
        case .movePreviousDisplay: return "Move to Previous Display"
        case .cycleWindow:         return "Cycle to Next Window"
        case .saveLayout:          return "Save Layout"
        case .restoreLayout:       return "Restore Layout"
        }
    }

    /// The factory-default bindings. `movePreviousDisplay` ships unbound — the
    /// menu still exposes it, and the user can assign a key in Preferences.
    static var defaultBindings: [HotkeyActionID: Shortcut] {
        let ctrlOpt = NSEvent.ModifierFlags([.control, .option]).rawValue
        func sc(_ key: Int) -> Shortcut { Shortcut(keyCode: UInt16(key), modifierFlags: ctrlOpt) }
        return [
            .snapLeftHalf:       sc(kVK_LeftArrow),
            .snapRightHalf:      sc(kVK_RightArrow),
            .snapTopHalf:        sc(kVK_UpArrow),
            .snapBottomHalf:     sc(kVK_DownArrow),
            .snapTopLeft:        sc(kVK_ANSI_U),
            .snapTopRight:       sc(kVK_ANSI_I),
            .snapBottomLeft:     sc(kVK_ANSI_J),
            .snapBottomRight:    sc(kVK_ANSI_K),
            .snapLeftThird:      sc(kVK_ANSI_1),
            .snapMiddleThird:    sc(kVK_ANSI_2),
            .snapRightThird:     sc(kVK_ANSI_3),
            .snapLeftTwoThirds:  sc(kVK_ANSI_4),
            .snapRightTwoThirds: sc(kVK_ANSI_5),
            .snapCenter:         sc(kVK_ANSI_C),
            .snapFull:           sc(kVK_Return),
            .moveNextDisplay:    sc(kVK_ANSI_M),
            .cycleWindow:        sc(kVK_Tab),
            .saveLayout:         sc(kVK_ANSI_S),
            .restoreLayout:      sc(kVK_ANSI_R),
        ]
    }
}
