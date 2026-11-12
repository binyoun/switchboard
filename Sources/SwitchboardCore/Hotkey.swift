import Foundation

/// A global shortcut parsed from text like "ctrl+option+b" or "cmd+shift+space".
public struct Hotkey: Equatable {
    /// macOS virtual key code (kVK_*).
    public let keyCode: UInt32
    /// Carbon modifier mask (cmdKey, shiftKey, optionKey, controlKey).
    public let modifiers: UInt32
    public let display: String

    static let cmd: UInt32 = 1 << 8, shift: UInt32 = 1 << 9, option: UInt32 = 1 << 11, control: UInt32 = 1 << 12

    static let keyCodes: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29,
        "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
        "space": 49, "return": 36, "tab": 48, "`": 50, "/": 44, ".": 47, ",": 43, ";": 41,
    ]

    public init?(_ spec: String) {
        var mods: UInt32 = 0
        var key: String?
        for part in spec.lowercased().split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            switch part {
            case "cmd", "command", "⌘": mods |= Hotkey.cmd
            case "shift", "⇧": mods |= Hotkey.shift
            case "opt", "option", "alt", "⌥": mods |= Hotkey.option
            case "ctrl", "control", "⌃": mods |= Hotkey.control
            default: key = part
            }
        }
        guard let key, let code = Hotkey.keyCodes[key], mods != 0 else { return nil }
        keyCode = code
        modifiers = mods
        var d = ""
        if mods & Hotkey.control != 0 { d += "⌃" }
        if mods & Hotkey.option != 0 { d += "⌥" }
        if mods & Hotkey.shift != 0 { d += "⇧" }
        if mods & Hotkey.cmd != 0 { d += "⌘" }
        display = d + (key == "space" ? "Space" : key == "return" ? "↩" : key == "tab" ? "⇥" : key.uppercased())
    }
}
