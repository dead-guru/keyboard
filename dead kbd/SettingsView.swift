import SwiftUI

struct SettingsView: View {
    @Bindable var appState: AppState

    var body: some View {
        NavigationStack {
            Form {
                Section("Touchpad") {
                    VStack(alignment: .leading) {
                        Text("Sensitivity: \(appState.settings.sensitivity, specifier: "%.1f")")
                        Slider(value: $appState.settings.sensitivity, in: 0.1...3.0, step: 0.1)
                    }
                    VStack(alignment: .leading) {
                        Text("Scroll Speed: \(appState.settings.scrollSpeed, specifier: "%.1f")")
                        Slider(value: $appState.settings.scrollSpeed, in: 0.1...3.0, step: 0.1)
                    }
                    Toggle("Natural Scrolling", isOn: $appState.settings.naturalScrolling)
                }

                Section("Feedback") {
                    Toggle("Haptic Feedback", isOn: $appState.settings.hapticFeedback)
                    Toggle("Click Sound", isOn: $appState.settings.clickSound)
                }

                Section("Keyboard") {
                    Picker("Input Protocol", selection: $appState.settings.inputProtocol) {
                        ForEach(InputProtocol.allCases, id: \.self) { proto in
                            Text(proto.rawValue).tag(proto)
                        }
                    }
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
