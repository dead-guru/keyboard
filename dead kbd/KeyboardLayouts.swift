import Foundation

protocol KeyboardLayout {
    var fKeyRow: [KeyDef] { get }
    var numberRow: [KeyDef] { get }
    var topRow: [KeyDef] { get }
    var homeRow: [KeyDef] { get }
    var bottomRow: [KeyDef] { get }
    var spaceRow: [KeyDef] { get }
    var allRows: [[KeyDef]] { get }
    var shiftedLabels: [String: String] { get }
    var globeKeyCodes: [(keyCode: UInt16, pressed: Bool)] { get }
}

extension KeyboardLayout {
    var allRows: [[KeyDef]] { [fKeyRow, numberRow, topRow, homeRow, bottomRow, spaceRow] }
}

// MARK: - Shared ANSI Rows

private let sharedFKeyRow: [KeyDef] = [
    KeyDef("esc", KeyCode.escape, style: .fkey),
    KeyDef("F1", KeyCode.f1, style: .fkey), KeyDef("F2", KeyCode.f2, style: .fkey),
    KeyDef("F3", KeyCode.f3, style: .fkey), KeyDef("F4", KeyCode.f4, style: .fkey),
    KeyDef("F5", KeyCode.f5, style: .fkey), KeyDef("F6", KeyCode.f6, style: .fkey),
    KeyDef("F7", KeyCode.f7, style: .fkey), KeyDef("F8", KeyCode.f8, style: .fkey),
    KeyDef("F9", KeyCode.f9, style: .fkey), KeyDef("F10", KeyCode.f10, style: .fkey),
    KeyDef("F11", KeyCode.f11, style: .fkey), KeyDef("F12", KeyCode.f12, style: .fkey),
    KeyDef("del", KeyCode.forwardDelete, style: .fkey),
]

private let sharedNumberRow: [KeyDef] = [
    KeyDef("`", KeyCode.grave), KeyDef("1", KeyCode.one), KeyDef("2", KeyCode.two),
    KeyDef("3", KeyCode.three), KeyDef("4", KeyCode.four), KeyDef("5", KeyCode.five),
    KeyDef("6", KeyCode.six), KeyDef("7", KeyCode.seven), KeyDef("8", KeyCode.eight),
    KeyDef("9", KeyCode.nine), KeyDef("0", KeyCode.zero),
    KeyDef("-", KeyCode.minus), KeyDef("=", KeyCode.equal),
    KeyDef("\u{232B}", KeyCode.delete, width: 1.5, style: .special),
]

private let sharedTopRow: [KeyDef] = [
    KeyDef("\u{21E5}", KeyCode.tab, width: 1.5, style: .special),
    KeyDef("Q", KeyCode.q), KeyDef("W", KeyCode.w), KeyDef("E", KeyCode.e),
    KeyDef("R", KeyCode.r), KeyDef("T", KeyCode.t), KeyDef("Y", KeyCode.y),
    KeyDef("U", KeyCode.u), KeyDef("I", KeyCode.i), KeyDef("O", KeyCode.o),
    KeyDef("P", KeyCode.p), KeyDef("[", KeyCode.leftBracket),
    KeyDef("]", KeyCode.rightBracket), KeyDef("\\", KeyCode.backslash),
]

private let sharedHomeRow: [KeyDef] = [
    KeyDef("\u{21EA}", KeyCode.capsLock, width: 1.75, isModifier: true),
    KeyDef("A", KeyCode.a), KeyDef("S", KeyCode.s), KeyDef("D", KeyCode.d),
    KeyDef("F", KeyCode.f), KeyDef("G", KeyCode.g), KeyDef("H", KeyCode.h),
    KeyDef("J", KeyCode.j), KeyDef("K", KeyCode.k), KeyDef("L", KeyCode.l),
    KeyDef(";", KeyCode.semicolon), KeyDef("'", KeyCode.quote),
    KeyDef("\u{21B5}", KeyCode.returnKey, width: 1.75, style: .special),
]

private let sharedBottomRow: [KeyDef] = [
    KeyDef("\u{21E7}", KeyCode.shift, width: 2.25, isModifier: true),
    KeyDef("Z", KeyCode.z), KeyDef("X", KeyCode.x), KeyDef("C", KeyCode.c),
    KeyDef("V", KeyCode.v), KeyDef("B", KeyCode.b), KeyDef("N", KeyCode.n),
    KeyDef("M", KeyCode.m), KeyDef(",", KeyCode.comma), KeyDef(".", KeyCode.period),
    KeyDef("/", KeyCode.slash),
    KeyDef("\u{21E7}", KeyCode.rightShift, width: 2.25, isModifier: true),
]

private let sharedShiftedLabels: [String: String] = [
    "`": "~", "1": "!", "2": "@", "3": "#", "4": "$", "5": "%",
    "6": "^", "7": "&", "8": "*", "9": "(", "0": ")",
    "-": "_", "=": "+", "[": "{", "]": "}", "\\": "|",
    ";": ":", "'": "\"", ",": "<", ".": ">", "/": "?",
]

// MARK: - macOS Layout

struct MacOSKeyboardLayout: KeyboardLayout {
    let fKeyRow = sharedFKeyRow
    let numberRow = sharedNumberRow
    let topRow = sharedTopRow
    let homeRow = sharedHomeRow
    let bottomRow = sharedBottomRow
    let shiftedLabels = sharedShiftedLabels

    // Ctrl+Space to switch language on macOS
    let globeKeyCodes: [(keyCode: UInt16, pressed: Bool)] = [
        (KeyCode.control, true),
        (KeyCode.space, true),
        (KeyCode.space, false),
        (KeyCode.control, false),
    ]

    let spaceRow: [KeyDef] = [
        KeyDef("globe", KeyCode.space, width: 1.0, isGlobe: true, style: .special),
        KeyDef("\u{2303}", KeyCode.control, width: 1.0, isModifier: true),
        KeyDef("\u{2325}", KeyCode.option, width: 1.0, isModifier: true),
        KeyDef("\u{2318}", KeyCode.command, width: 1.25, isModifier: true),
        KeyDef("", KeyCode.space, width: 5.25),
        KeyDef("\u{2318}", KeyCode.command, width: 1.0, isModifier: true),
        KeyDef("\u{2325}", KeyCode.rightOption, width: 1.0, isModifier: true),
        KeyDef("\u{25C0}", KeyCode.leftArrow, style: .special),
        KeyDef("\u{25B2}", KeyCode.upArrow, width: 1.0, style: .special),
        KeyDef("\u{25B6}", KeyCode.rightArrow, style: .special),
    ]
}

// MARK: - Linux Layout

struct LinuxKeyboardLayout: KeyboardLayout {
    let fKeyRow = sharedFKeyRow
    let numberRow = sharedNumberRow
    let topRow = sharedTopRow
    let homeRow = sharedHomeRow
    let bottomRow = sharedBottomRow
    let shiftedLabels = sharedShiftedLabels

    // Super+Space to switch language on Linux
    let globeKeyCodes: [(keyCode: UInt16, pressed: Bool)] = [
        (KeyCode.command, true),
        (KeyCode.space, true),
        (KeyCode.space, false),
        (KeyCode.command, false),
    ]

    let spaceRow: [KeyDef] = [
        KeyDef("globe", KeyCode.space, width: 1.0, isGlobe: true, style: .special),
        KeyDef("Ctrl", KeyCode.control, width: 1.0, isModifier: true),
        KeyDef("Alt", KeyCode.option, width: 1.0, isModifier: true),
        KeyDef("Super", KeyCode.command, width: 1.25, isModifier: true),
        KeyDef("", KeyCode.space, width: 5.25),
        KeyDef("Super", KeyCode.command, width: 1.0, isModifier: true),
        KeyDef("Alt", KeyCode.rightOption, width: 1.0, isModifier: true),
        KeyDef("\u{25C0}", KeyCode.leftArrow, style: .special),
        KeyDef("\u{25B2}", KeyCode.upArrow, width: 1.0, style: .special),
        KeyDef("\u{25B6}", KeyCode.rightArrow, style: .special),
    ]
}

// MARK: - Factory

enum KeyboardLayoutFactory {
    static func create(for platform: ServerPlatform) -> KeyboardLayout {
        switch platform {
        case .macOS:
            return MacOSKeyboardLayout()
        case .linux:
            return LinuxKeyboardLayout()
        case .windows:
            // Windows uses same labels as Linux for now
            return LinuxKeyboardLayout()
        }
    }
}
