import SwiftUI

enum InputMode: String, CaseIterable {
    case keyboard = "Keyboard"
    case touchpad = "Touchpad"
    case combined = "Combined"
}

struct ContentView: View {
    @Bindable var appState: AppState

    var body: some View {
        if appState.isConnected {
            InputView(appState: appState)
        } else {
            NavigationStack {
                ConnectionsView(appState: appState)
            }
        }
    }
}

struct InputView: View {
    @Bindable var appState: AppState
    @State private var mode: InputMode = .combined
    @State private var showSettings = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        NavigationStack {
            inputContent
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            appState.disconnect()
                        } label: {
                            Image(systemName: "xmark.circle")
                                .foregroundStyle(.red)
                        }
                    }

                    ToolbarItem(placement: .principal) {
                        if horizontalSizeClass == .compact {
                            Menu {
                                Picker("Mode", selection: $mode) {
                                    ForEach(InputMode.allCases, id: \.self) { m in
                                        Text(m.rawValue).tag(m)
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(mode.rawValue)
                                        .font(.subheadline.weight(.semibold))
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.caption2.weight(.bold))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(.white.opacity(0.12), in: Capsule())
                            }
                        } else {
                            Picker("Mode", selection: $mode) {
                                ForEach(InputMode.allCases, id: \.self) { m in
                                    Text(m.rawValue).tag(m)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 320)
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
                .toolbarBackgroundVisibility(.visible, for: .navigationBar)
                .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) {
            SettingsView(appState: appState)
        }
        .persistentSystemOverlays(.hidden)
    }

    @ViewBuilder
    private var inputContent: some View {
        let layout = KeyboardLayoutFactory.create(for: appState.client.platform)
        switch mode {
        case .keyboard:
            KeyboardView(layout: layout, client: appState.client, hapticEnabled: appState.settings.hapticFeedback, clickSoundEnabled: appState.settings.clickSound, inputProtocol: appState.settings.inputProtocol)
        case .touchpad:
            TouchpadView(client: appState.client, settings: appState.settings)
        case .combined:
            CombinedInputView(layout: layout, client: appState.client, settings: appState.settings, inputProtocol: appState.settings.inputProtocol)
        }
    }
}

// MARK: - Combined Input View

struct CombinedInputView: View {
    let layout: KeyboardLayout
    let client: WebSocketClient
    let settings: AppSettings
    let inputProtocol: InputProtocol

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 4
            let fKeyScale: CGFloat = 0.65
            let mainRows: CGFloat = 5
            let totalUnits = layout.numberRow.map(\.width).reduce(0, +)
            let totalHSpacing = spacing * CGFloat(layout.numberRow.count + 1)
            let unitWidth = (geo.size.width - totalHSpacing) / totalUnits
            let totalVSpacing = spacing * (mainRows + 2)
            let cappedMainKeyHeight = unitWidth * 1.4
            let idealKeyboardHeight = cappedMainKeyHeight * (mainRows + fKeyScale) + totalVSpacing
            let keyboardHeight = min(idealKeyboardHeight, geo.size.height * 0.65)

            let isLandscape = geo.size.width > geo.size.height
            let touchpadHeight = isLandscape ? nil : (geo.size.height - keyboardHeight - 1) / 2

            VStack(spacing: 0) {
                if let touchpadHeight {
                    Spacer()
                        .frame(height: touchpadHeight)
                }

                KeyboardView(layout: layout, client: client, hapticEnabled: settings.hapticFeedback, clickSoundEnabled: settings.clickSound, inputProtocol: inputProtocol)
                    .frame(height: keyboardHeight)

                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 1)

                TouchpadView(client: client, settings: settings)
                    .frame(height: touchpadHeight)
            }
        }
    }
}
