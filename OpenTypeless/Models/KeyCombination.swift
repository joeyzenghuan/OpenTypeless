import Foundation
import Carbon
import Cocoa

/// Represents a keyboard shortcut combination of modifier keys and an optional regular key.
/// Supports serialization to/from JSON for UserDefaults storage.
struct KeyCombination: Codable, Equatable {

    // MARK: - Modifier Flags

    var hasCommand: Bool = false
    var hasOption: Bool = false
    var hasControl: Bool = false
    var hasShift: Bool = false
    var hasFunction: Bool = false

    // MARK: - Key (optional, for non-modifier-only shortcuts)

    /// The virtual key code (Carbon key code). Nil means modifier-only shortcut (e.g., fn alone).
    var keyCode: UInt16?

    // MARK: - Computed Properties

    /// True if this combination includes at least one modifier or a key.
    var isValid: Bool {
        return hasCommand || hasOption || hasControl || hasShift || hasFunction || keyCode != nil
    }

    /// True if this is a modifier-only shortcut (no regular key).
    var isModifierOnly: Bool {
        return keyCode == nil
    }

    /// Returns the NSEvent.ModifierFlags matching this combination (excluding fn, which is handled separately).
    var modifierFlags: NSEvent.ModifierFlags {
        var flags = NSEvent.ModifierFlags()
        if hasCommand { flags.insert(.command) }
        if hasOption { flags.insert(.option) }
        if hasControl { flags.insert(.control) }
        if hasShift { flags.insert(.shift) }
        if hasFunction { flags.insert(.function) }
        return flags
    }

    /// The set of non-fn modifier flags for comparison purposes.
    var nonFnModifierFlags: NSEvent.ModifierFlags {
        var flags = NSEvent.ModifierFlags()
        if hasCommand { flags.insert(.command) }
        if hasOption { flags.insert(.option) }
        if hasControl { flags.insert(.control) }
        if hasShift { flags.insert(.shift) }
        return flags
    }

    /// Human-readable display string using standard macOS symbols.
    var displayString: String {
        var parts: [String] = []

        if hasFunction { parts.append("fn") }
        if hasControl { parts.append("\u{2303}") }  // ⌃
        if hasOption { parts.append("\u{2325}") }    // ⌥
        if hasShift { parts.append("\u{21E7}") }     // ⇧
        if hasCommand { parts.append("\u{2318}") }   // ⌘

        if let keyCode = keyCode {
            parts.append(KeyCombination.keyCodeToDisplayString(keyCode))
        }

        return parts.joined()
    }

    // MARK: - Serialization

    /// Encode to JSON string for storage in UserDefaults.
    func toJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(self),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    /// Decode from JSON string.
    static func fromJSON(_ json: String) -> KeyCombination? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(KeyCombination.self, from: data)
    }

    /// Parse from legacy string format (e.g., "fn", "fn+space", "fn+left").
    static func fromLegacyString(_ string: String) -> KeyCombination {
        var combo = KeyCombination()
        let parts = string.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }

        for part in parts {
            switch part {
            case "fn":
                combo.hasFunction = true
            case "cmd", "command":
                combo.hasCommand = true
            case "opt", "option", "alt":
                combo.hasOption = true
            case "ctrl", "control":
                combo.hasControl = true
            case "shift":
                combo.hasShift = true
            case "space":
                combo.keyCode = 49 // kVK_Space
            case "left":
                combo.keyCode = 123 // kVK_LeftArrow
            case "right":
                combo.keyCode = 124 // kVK_RightArrow
            case "up":
                combo.keyCode = 126 // kVK_UpArrow
            case "down":
                combo.keyCode = 125 // kVK_DownArrow
            case "return", "enter":
                combo.keyCode = 36 // kVK_Return
            case "tab":
                combo.keyCode = 48 // kVK_Tab
            case "escape", "esc":
                combo.keyCode = 53 // kVK_Escape
            case "delete", "backspace":
                combo.keyCode = 51 // kVK_Delete
            default:
                // Try to interpret as a single character key
                if let char = part.first, part.count == 1 {
                    if let code = KeyCombination.charToKeyCode(char) {
                        combo.keyCode = code
                    }
                }
            }
        }

        return combo
    }

    /// Create from an NSEvent (used for recording shortcuts).
    static func fromEvent(_ event: NSEvent) -> KeyCombination {
        var combo = KeyCombination()

        let flags = event.modifierFlags
        combo.hasCommand = flags.contains(.command)
        combo.hasOption = flags.contains(.option)
        combo.hasControl = flags.contains(.control)
        combo.hasShift = flags.contains(.shift)
        combo.hasFunction = flags.contains(.function)

        // For flagsChanged events, there's no keyCode for the actual key
        if event.type != .flagsChanged {
            combo.keyCode = event.keyCode
        }

        return combo
    }

    /// Create a modifier-only combination from flags (used for recording modifier-only shortcuts).
    static func fromModifierFlags(_ flags: NSEvent.ModifierFlags) -> KeyCombination {
        var combo = KeyCombination()
        combo.hasCommand = flags.contains(.command)
        combo.hasOption = flags.contains(.option)
        combo.hasControl = flags.contains(.control)
        combo.hasShift = flags.contains(.shift)
        combo.hasFunction = flags.contains(.function)
        return combo
    }

    // MARK: - Matching

    /// Check if a key event matches this combination.
    func matchesKeyEvent(_ event: NSEvent) -> Bool {
        guard let expectedKeyCode = keyCode else { return false }
        guard event.keyCode == expectedKeyCode else { return false }

        let eventFlags = event.modifierFlags
        let relevantFlags: [(Bool, NSEvent.ModifierFlags)] = [
            (hasCommand, .command),
            (hasOption, .option),
            (hasControl, .control),
            (hasShift, .shift),
            (hasFunction, .function),
        ]

        for (expected, flag) in relevantFlags {
            if expected != eventFlags.contains(flag) {
                return false
            }
        }

        return true
    }

    /// Check if modifier flags match this combination (for modifier-only shortcuts).
    func matchesModifierFlags(_ flags: NSEvent.ModifierFlags) -> Bool {
        guard isModifierOnly else { return false }

        let relevantFlags: [(Bool, NSEvent.ModifierFlags)] = [
            (hasCommand, .command),
            (hasOption, .option),
            (hasControl, .control),
            (hasShift, .shift),
            (hasFunction, .function),
        ]

        for (expected, flag) in relevantFlags {
            if expected != flags.contains(flag) {
                return false
            }
        }

        return true
    }

    // MARK: - Key Code Display Mapping

    /// Convert a virtual key code to a human-readable display string.
    static func keyCodeToDisplayString(_ keyCode: UInt16) -> String {
        switch Int(keyCode) {
        // Letters
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"

        // Numbers
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"

        // Special keys
        case kVK_Space: return "Space"
        case kVK_Return: return "\u{21A9}"         // ↩
        case kVK_Tab: return "\u{21E5}"             // ⇥
        case kVK_Delete: return "\u{232B}"          // ⌫
        case kVK_ForwardDelete: return "\u{2326}"   // ⌦
        case kVK_Escape: return "\u{238B}"          // ⎋
        case kVK_Home: return "\u{2196}"            // ↖
        case kVK_End: return "\u{2198}"             // ↘
        case kVK_PageUp: return "\u{21DE}"          // ⇞
        case kVK_PageDown: return "\u{21DF}"        // ⇟

        // Arrow keys
        case kVK_LeftArrow: return "\u{2190}"       // ←
        case kVK_RightArrow: return "\u{2192}"      // →
        case kVK_UpArrow: return "\u{2191}"         // ↑
        case kVK_DownArrow: return "\u{2193}"       // ↓

        // Function keys
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_F13: return "F13"
        case kVK_F14: return "F14"
        case kVK_F15: return "F15"

        // Symbols
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Grave: return "`"

        default:
            return "Key(\(keyCode))"
        }
    }

    /// Convert a character to a virtual key code.
    private static func charToKeyCode(_ char: Character) -> UInt16? {
        let mapping: [Character: UInt16] = [
            "a": UInt16(kVK_ANSI_A), "b": UInt16(kVK_ANSI_B), "c": UInt16(kVK_ANSI_C),
            "d": UInt16(kVK_ANSI_D), "e": UInt16(kVK_ANSI_E), "f": UInt16(kVK_ANSI_F),
            "g": UInt16(kVK_ANSI_G), "h": UInt16(kVK_ANSI_H), "i": UInt16(kVK_ANSI_I),
            "j": UInt16(kVK_ANSI_J), "k": UInt16(kVK_ANSI_K), "l": UInt16(kVK_ANSI_L),
            "m": UInt16(kVK_ANSI_M), "n": UInt16(kVK_ANSI_N), "o": UInt16(kVK_ANSI_O),
            "p": UInt16(kVK_ANSI_P), "q": UInt16(kVK_ANSI_Q), "r": UInt16(kVK_ANSI_R),
            "s": UInt16(kVK_ANSI_S), "t": UInt16(kVK_ANSI_T), "u": UInt16(kVK_ANSI_U),
            "v": UInt16(kVK_ANSI_V), "w": UInt16(kVK_ANSI_W), "x": UInt16(kVK_ANSI_X),
            "y": UInt16(kVK_ANSI_Y), "z": UInt16(kVK_ANSI_Z),
            "0": UInt16(kVK_ANSI_0), "1": UInt16(kVK_ANSI_1), "2": UInt16(kVK_ANSI_2),
            "3": UInt16(kVK_ANSI_3), "4": UInt16(kVK_ANSI_4), "5": UInt16(kVK_ANSI_5),
            "6": UInt16(kVK_ANSI_6), "7": UInt16(kVK_ANSI_7), "8": UInt16(kVK_ANSI_8),
            "9": UInt16(kVK_ANSI_9),
        ]
        return mapping[char]
    }

    // MARK: - Defaults

    /// Default shortcut for voice input: fn
    static let defaultVoiceInput = KeyCombination(hasFunction: true)

    /// Default shortcut for hands-free mode: fn+Space
    static let defaultHandsFree = KeyCombination(hasFunction: true, keyCode: UInt16(kVK_Space))

    /// Default shortcut for translate: fn+Left Arrow
    static let defaultTranslate = KeyCombination(hasFunction: true, keyCode: UInt16(kVK_LeftArrow))
}
