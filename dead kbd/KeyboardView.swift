import SwiftUI
import UIKit
import AudioToolbox

enum KeyStyle { case letter, special, modifier, fkey }
enum ModifierState { case inactive, oneShot, locked }
enum InputLanguage { case english, ukrainian }

struct KeyDef: Identifiable {
    let id = UUID()
    let label: String
    let keyCode: UInt16
    let width: CGFloat
    let isModifier: Bool
    let isGlobe: Bool
    let style: KeyStyle

    init(_ label: String, _ keyCode: UInt16, width: CGFloat = 1.0, isModifier: Bool = false, isGlobe: Bool = false, style: KeyStyle = .letter) {
        self.label = label
        self.keyCode = keyCode
        self.width = width
        self.isModifier = isModifier
        self.isGlobe = isGlobe
        self.style = isModifier ? .modifier : style
    }
}

// MARK: - Ukrainian Secondary Labels

private let ukrainianLabels: [String: String] = [
    "Q": "Й", "W": "Ц", "E": "У", "R": "К", "T": "Е",
    "Y": "Н", "U": "Г", "I": "Ш", "O": "Щ", "P": "З",
    "A": "Ф", "S": "І", "D": "В", "F": "А", "G": "П",
    "H": "Р", "J": "О", "K": "Л", "L": "Д",
    "Z": "Я", "X": "Ч", "C": "С", "V": "М", "B": "И",
    "N": "Т", "M": "Ь",
    "[": "Х", "]": "Ї", "\\": "Ґ",
    ";": "Ж", "'": "Є",
    ",": "Б", ".": "Ю",
]

// MARK: - Colors

enum KeyColors {
    static let bg = Color(white: 0.05)
    static let letterTop = Color(white: 0.30)
    static let letterBottom = Color(white: 0.22)
    static let specialTop = Color(white: 0.20)
    static let specialBottom = Color(white: 0.14)
    static let modifierTop = Color(white: 0.20)
    static let modifierBottom = Color(white: 0.14)
    static let fkeyTop = Color(white: 0.18)
    static let fkeyBottom = Color(white: 0.12)
    static let pressed = Color(white: 0.42)
    static let activeModifier = Color.accentColor
}

// MARK: - KeyboardView

struct KeyboardView: View {
    let layout: KeyboardLayout
    let client: WebSocketClient
    let hapticEnabled: Bool
    let clickSoundEnabled: Bool
    let inputProtocol: InputProtocol
    @State private var modifierStates: [UInt16: ModifierState] = [:]
    @State private var modifierLastTapTime: [UInt16: Date] = [:]
    @State private var inputLanguage: InputLanguage = .english

    private var isShiftActive: Bool {
        modifierStates[KeyCode.shift] != nil || modifierStates[KeyCode.rightShift] != nil
    }

    private var commandModifierActive: Bool {
        let keys: Set<UInt16> = [KeyCode.command, KeyCode.control, KeyCode.option, KeyCode.rightOption, KeyCode.rightControl]
        return modifierStates.keys.contains(where: keys.contains)
    }

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 4
            let fKeyScale: CGFloat = 0.65
            let mainRows: CGFloat = 5
            let totalUnits = layout.numberRow.map(\.width).reduce(0, +)
            let totalHSpacing = spacing * CGFloat(layout.numberRow.count + 1)
            let unitWidth = (geo.size.width - totalHSpacing) / totalUnits
            let totalVSpacing = spacing * (mainRows + 2)
            let availableHeight = geo.size.height - totalVSpacing
            let mainKeyHeight = min(availableHeight / (mainRows + fKeyScale), unitWidth * 1.4)
            let fKeyHeight = mainKeyHeight * fKeyScale

            VStack(spacing: spacing) {
                keyRowView(layout.fKeyRow, unitWidth: unitWidth, keyHeight: fKeyHeight, spacing: spacing)
                ForEach(Array(layout.allRows.dropFirst().enumerated()), id: \.offset) { _, row in
                    keyRowView(row, unitWidth: unitWidth, keyHeight: mainKeyHeight, spacing: spacing)
                }
            }
            .padding(spacing)
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .background(KeyColors.bg)
    }

    private func handleModifierTap(keyCode: UInt16) {
        if keyCode == KeyCode.capsLock {
            if modifierStates[keyCode] != nil {
                modifierStates[keyCode] = nil
            } else {
                modifierStates[keyCode] = .locked
            }
            client.sendKeyEvent(keyCode: keyCode, pressed: true)
            client.sendKeyEvent(keyCode: keyCode, pressed: false)
            return
        }

        let currentState = modifierStates[keyCode] ?? .inactive
        let now = Date.now
        let lastTap = modifierLastTapTime[keyCode] ?? .distantPast
        let isDoubleTap = now.timeIntervalSince(lastTap) < 0.3
        modifierLastTapTime[keyCode] = now

        switch currentState {
        case .inactive:
            modifierStates[keyCode] = isDoubleTap ? .locked : .oneShot
            client.sendKeyEvent(keyCode: keyCode, pressed: true)
        case .oneShot:
            if isDoubleTap {
                modifierStates[keyCode] = .locked
            } else {
                modifierStates[keyCode] = nil
                client.sendKeyEvent(keyCode: keyCode, pressed: false)
            }
        case .locked:
            modifierStates[keyCode] = nil
            client.sendKeyEvent(keyCode: keyCode, pressed: false)
        }
    }

    private func releaseOneShotModifiers() {
        for (keyCode, state) in modifierStates where state == .oneShot {
            modifierStates[keyCode] = nil
            client.sendKeyEvent(keyCode: keyCode, pressed: false)
        }
    }

    private func keyRowView(_ keys: [KeyDef], unitWidth: CGFloat, keyHeight: CGFloat, spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(keys) { key in
                if key.label == "\u{25B2}" {
                    VStack(spacing: 2) {
                        ArrowHalfKey(label: "\u{25B2}", keyCode: KeyCode.upArrow, width: unitWidth * key.width, height: keyHeight / 2 - 1, client: client, hapticEnabled: hapticEnabled, clickSoundEnabled: clickSoundEnabled)
                        ArrowHalfKey(label: "\u{25BC}", keyCode: KeyCode.downArrow, width: unitWidth * key.width, height: keyHeight / 2 - 1, client: client, hapticEnabled: hapticEnabled, clickSoundEnabled: clickSoundEnabled)
                    }
                    .frame(width: unitWidth * key.width, height: keyHeight)
                } else if key.isGlobe {
                    GlobeKeyView(width: unitWidth * key.width, height: keyHeight, hapticEnabled: hapticEnabled, clickSoundEnabled: clickSoundEnabled, inputLanguage: inputLanguage, inputProtocol: inputProtocol, onGlobeTap: {
                        if inputProtocol == .typeText {
                            inputLanguage = inputLanguage == .english ? .ukrainian : .english
                        } else {
                            for kc in layout.globeKeyCodes {
                                client.sendKeyEvent(keyCode: kc.keyCode, pressed: kc.pressed)
                            }
                        }
                    })
                } else {
                    KeyView(
                        key: key,
                        width: unitWidth * key.width,
                        height: keyHeight,
                        isModifierActive: modifierStates[key.keyCode] != nil,
                        isShiftActive: isShiftActive,
                        isCommandModifierActive: commandModifierActive,
                        inputLanguage: inputLanguage,
                        inputProtocol: inputProtocol,
                        shiftedLabels: layout.shiftedLabels,
                        client: client,
                        hapticEnabled: hapticEnabled,
                        clickSoundEnabled: clickSoundEnabled,
                        onModifierTap: key.isModifier ? {
                            handleModifierTap(keyCode: key.keyCode)
                        } : nil,
                        onNonModifierKeyUp: !key.isModifier ? {
                            releaseOneShotModifiers()
                        } : nil
                    )
                }
            }
        }
    }
}

// MARK: - Globe Key

struct GlobeKeyView: View {
    let width: CGFloat
    let height: CGFloat
    let hapticEnabled: Bool
    let clickSoundEnabled: Bool
    let inputLanguage: InputLanguage
    let inputProtocol: InputProtocol
    let onGlobeTap: () -> Void
    @State private var isPressed = false

    private var globeLabel: String {
        if inputProtocol == .keyCode { return "Lang" }
        return inputLanguage == .english ? "EN" : "UA"
    }

    var body: some View {
        VStack(spacing: 1) {
            Image(systemName: "globe")
                .font(.system(size: max(min(width, height) * 0.25, 8), weight: .medium))
            Text(globeLabel)
                .font(.system(size: max(min(width, height) * 0.16, 7), weight: .semibold, design: .monospaced))
        }
        .foregroundStyle(.white.opacity(0.9))
        .frame(width: width, height: height)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(
                    isPressed
                    ? AnyShapeStyle(KeyColors.pressed)
                    : AnyShapeStyle(LinearGradient(colors: [KeyColors.specialTop, KeyColors.specialBottom], startPoint: .top, endPoint: .bottom))
                )
                .shadow(color: .black.opacity(0.5), radius: 1, y: 1)
        )
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(duration: 0.15), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressed else { return }
                    isPressed = true
                    onGlobeTap()
                    if hapticEnabled { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                    if clickSoundEnabled { AudioServicesPlaySystemSound(1104) }
                }
                .onEnded { _ in
                    isPressed = false
                }
        )
    }
}

// MARK: - Arrow Half Key

struct ArrowHalfKey: View {
    let label: String
    let keyCode: UInt16
    let width: CGFloat
    let height: CGFloat
    let client: WebSocketClient
    let hapticEnabled: Bool
    let clickSoundEnabled: Bool
    @State private var isPressed = false
    @State private var repeatTask: Task<Void, Never>?

    var body: some View {
        Text(label)
            .font(.system(size: max(min(width, height) * 0.5, 8)))
            .foregroundStyle(.white.opacity(0.85))
            .frame(width: width, height: height)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(
                        isPressed
                        ? AnyShapeStyle(KeyColors.pressed)
                        : AnyShapeStyle(LinearGradient(colors: [KeyColors.specialTop, KeyColors.specialBottom], startPoint: .top, endPoint: .bottom))
                    )
                    .shadow(color: .black.opacity(0.5), radius: 0.5, y: 0.5)
            )
            .scaleEffect(isPressed ? 0.93 : 1.0)
            .animation(.spring(duration: 0.12), value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                            client.sendKeyEvent(keyCode: keyCode, pressed: true)
                            startRepeat()
                            if hapticEnabled { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                            if clickSoundEnabled { AudioServicesPlaySystemSound(1104) }
                        }
                    }
                    .onEnded { _ in
                        isPressed = false
                        stopRepeat()
                        client.sendKeyEvent(keyCode: keyCode, pressed: false)
                    }
            )
    }

    private func startRepeat() {
        repeatTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            while !Task.isCancelled {
                client.sendKeyEvent(keyCode: keyCode, pressed: true)
                try? await Task.sleep(for: .milliseconds(35))
            }
        }
    }

    private func stopRepeat() {
        repeatTask?.cancel()
        repeatTask = nil
    }
}

// MARK: - Key View

struct KeyView: View {
    let key: KeyDef
    let width: CGFloat
    let height: CGFloat
    let isModifierActive: Bool
    let isShiftActive: Bool
    let isCommandModifierActive: Bool
    let inputLanguage: InputLanguage
    let inputProtocol: InputProtocol
    let shiftedLabels: [String: String]
    let client: WebSocketClient
    let hapticEnabled: Bool
    let clickSoundEnabled: Bool
    var onModifierTap: (() -> Void)?
    var onNonModifierKeyUp: (() -> Void)?
    @State private var isPressed = false
    @State private var repeatTask: Task<Void, Never>?
    @State private var lastSpaceTapTime: Date = .distantPast
    @State private var isSpaceSwiping = false
    @State private var spaceSwipeLastX: CGFloat = 0

    private var isCharKey: Bool { key.label.count == 1 && key.style == .letter }
    private var isFKey: Bool { key.style == .fkey }

    private var isLetter: Bool {
        key.label.count == 1 && key.style == .letter && key.label.first?.isLetter == true
    }

    private var isCharacterKey: Bool {
        key.style == .letter && key.keyCode != KeyCode.space
    }

    private var characterToType: String {
        if inputLanguage == .ukrainian, let ukr = ukrainianLabels[key.label] {
            return isShiftActive ? ukr : ukr.lowercased()
        }
        if isShiftActive {
            return shiftedLabels[key.label] ?? key.label
        }
        if isLetter { return key.label.lowercased() }
        return key.label
    }

    private var displayLabel: String {
        if key.keyCode == KeyCode.space { return "" }
        if isCharacterKey { return characterToType }
        return key.label
    }

    private var secondaryLabel: String? {
        guard isCharacterKey else { return nil }
        if inputLanguage == .ukrainian {
            guard ukrainianLabels[key.label] != nil else { return nil }
            if isShiftActive { return shiftedLabels[key.label] ?? key.label }
            return isLetter ? key.label.lowercased() : key.label
        } else {
            guard let ukr = ukrainianLabels[key.label] else { return nil }
            return isShiftActive ? ukr : ukr.lowercased()
        }
    }

    var body: some View {
        Group {
            if key.keyCode == KeyCode.space {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(.white.opacity(0.2))
                    .frame(width: 40, height: 3)
            } else if let secondary = secondaryLabel {
                VStack(spacing: 0) {
                    Text(displayLabel)
                        .font(keyFont)
                        .foregroundStyle(textColor)
                    Text(secondary)
                        .font(.system(size: max(min(width, height) * 0.24, 7), weight: .regular, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                }
            } else {
                Text(displayLabel)
                    .font(keyFont)
            }
        }
        .foregroundStyle(textColor)
        .frame(width: width, height: height)
        .background(
            RoundedRectangle(cornerRadius: isFKey ? 5 : 7, style: .continuous)
                .fill(backgroundFill)
                .shadow(color: .black.opacity(isFKey ? 0.3 : 0.5), radius: isFKey ? 0.5 : 1, y: isFKey ? 0.5 : 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: isFKey ? 5 : 7, style: .continuous)
                .strokeBorder(.white.opacity(isPressed ? 0.12 : 0.04), lineWidth: 0.5)
        )
        .scaleEffect(isPressed ? 0.94 : 1.0)
        .animation(.spring(duration: 0.15), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if key.keyCode == KeyCode.space && key.label.isEmpty {
                        if !isPressed {
                            isPressed = true
                            isSpaceSwiping = false
                            spaceSwipeLastX = value.startLocation.x
                            if hapticEnabled { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                            if clickSoundEnabled { AudioServicesPlaySystemSound(1104) }
                        }
                        let dx = value.location.x - value.startLocation.x
                        if !isSpaceSwiping && abs(dx) > 10 {
                            isSpaceSwiping = true
                            spaceSwipeLastX = value.location.x
                        }
                        if isSpaceSwiping {
                            let delta = value.location.x - spaceSwipeLastX
                            let step: CGFloat = 12
                            let steps = Int(delta / step)
                            if steps != 0 {
                                let arrow = steps > 0 ? KeyCode.rightArrow : KeyCode.leftArrow
                                for _ in 0..<abs(steps) {
                                    client.sendKeyEvent(keyCode: arrow, pressed: true)
                                    client.sendKeyEvent(keyCode: arrow, pressed: false)
                                }
                                spaceSwipeLastX += CGFloat(steps) * step
                            }
                        }
                        return
                    }
                    guard !isPressed else { return }
                    isPressed = true
                    if key.isModifier {
                        onModifierTap?()
                    } else if isCharacterKey && !isCommandModifierActive && inputProtocol == .typeText {
                        client.sendTypeText(characterToType)
                        startTextRepeat()
                    } else {
                        client.sendKeyEvent(keyCode: key.keyCode, pressed: true)
                        startRepeat()
                    }
                    if hapticEnabled { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                    if clickSoundEnabled { AudioServicesPlaySystemSound(1104) }
                }
                .onEnded { _ in
                    isPressed = false
                    if key.keyCode == KeyCode.space && key.label.isEmpty {
                        if isSpaceSwiping {
                            isSpaceSwiping = false
                        } else {
                            let now = Date.now
                            if now.timeIntervalSince(lastSpaceTapTime) < 0.3 {
                                client.sendKeyEvent(keyCode: KeyCode.delete, pressed: true)
                                client.sendKeyEvent(keyCode: KeyCode.delete, pressed: false)
                                if inputProtocol == .typeText {
                                    client.sendTypeText(". ")
                                } else {
                                    client.sendKeyEvent(keyCode: KeyCode.period, pressed: true)
                                    client.sendKeyEvent(keyCode: KeyCode.period, pressed: false)
                                    client.sendKeyEvent(keyCode: KeyCode.space, pressed: true)
                                    client.sendKeyEvent(keyCode: KeyCode.space, pressed: false)
                                }
                                lastSpaceTapTime = .distantPast
                            } else {
                                client.sendKeyEvent(keyCode: KeyCode.space, pressed: true)
                                client.sendKeyEvent(keyCode: KeyCode.space, pressed: false)
                                lastSpaceTapTime = now
                            }
                            onNonModifierKeyUp?()
                        }
                    } else if isCharacterKey && !isCommandModifierActive && inputProtocol == .typeText {
                        stopRepeat()
                        onNonModifierKeyUp?()
                    } else if !key.isModifier {
                        stopRepeat()
                        client.sendKeyEvent(keyCode: key.keyCode, pressed: false)
                        onNonModifierKeyUp?()
                    }
                }
        )
    }

    private func startTextRepeat() {
        repeatTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            while !Task.isCancelled {
                client.sendTypeText(characterToType)
                try? await Task.sleep(for: .milliseconds(35))
            }
        }
    }

    private func startRepeat() {
        repeatTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            while !Task.isCancelled {
                client.sendKeyEvent(keyCode: key.keyCode, pressed: true)
                try? await Task.sleep(for: .milliseconds(35))
            }
        }
    }

    private func stopRepeat() {
        repeatTask?.cancel()
        repeatTask = nil
    }

    private var keyFont: Font {
        let hasSecondary = secondaryLabel != nil
        let size: CGFloat
        if isFKey {
            size = max(min(width, height) * 0.38, 8)
        } else if isCharKey {
            size = max(min(width, height) * (hasSecondary ? 0.34 : 0.42), 10)
        } else {
            size = max(min(width, height) * 0.30, 8)
        }
        let design: Font.Design = isCharKey ? .monospaced : .default
        let weight: Font.Weight = isCharKey ? .regular : .medium
        return .system(size: size, weight: weight, design: design)
    }

    private var textColor: Color {
        if key.isModifier && isModifierActive { return .white }
        if isFKey { return .white.opacity(0.6) }
        if isCharKey { return .white.opacity(0.95) }
        return .white.opacity(0.85)
    }

    private var backgroundFill: AnyShapeStyle {
        if key.isModifier && isModifierActive {
            return AnyShapeStyle(LinearGradient(
                colors: [KeyColors.activeModifier.opacity(0.9), KeyColors.activeModifier],
                startPoint: .top, endPoint: .bottom
            ))
        } else if isPressed {
            return AnyShapeStyle(KeyColors.pressed)
        } else {
            switch key.style {
            case .letter:
                return AnyShapeStyle(LinearGradient(colors: [KeyColors.letterTop, KeyColors.letterBottom], startPoint: .top, endPoint: .bottom))
            case .special:
                return AnyShapeStyle(LinearGradient(colors: [KeyColors.specialTop, KeyColors.specialBottom], startPoint: .top, endPoint: .bottom))
            case .modifier:
                return AnyShapeStyle(LinearGradient(colors: [KeyColors.modifierTop, KeyColors.modifierBottom], startPoint: .top, endPoint: .bottom))
            case .fkey:
                return AnyShapeStyle(LinearGradient(colors: [KeyColors.fkeyTop, KeyColors.fkeyBottom], startPoint: .top, endPoint: .bottom))
            }
        }
    }
}
