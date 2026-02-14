import SwiftUI

@Observable
final class AppState {
    var connections: [ServerConnection] = [] {
        didSet { saveConnections() }
    }
    var settings: AppSettings = AppSettings() {
        didSet { saveSettings() }
    }
    var activeConnection: ServerConnection?
    var isConnected: Bool = false
    var connectionError: String?
    let client = WebSocketClient()

    private let connectionsKey = "savedConnections"
    private let settingsKey = "appSettings"
    private var monitorTask: Task<Void, Never>?

    init() {
        loadConnections()
        loadSettings()
    }

    func connect(to server: ServerConnection) async {
        connectionError = nil
        let success = await client.connect(to: server)
        if success {
            activeConnection = server
            isConnected = true
            connectionError = nil
            startMonitoringConnection()
        } else {
            connectionError = client.connectionError
            isConnected = false
        }
    }

    func disconnect() {
        monitorTask?.cancel()
        monitorTask = nil
        client.disconnect()
        activeConnection = nil
        isConnected = false
        connectionError = nil
    }

    private func startMonitoringConnection() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if !self.client.isConnected && self.isConnected {
                    self.connectionError = self.client.connectionError
                    self.isConnected = false
                    self.activeConnection = nil
                    break
                }
            }
        }
    }

    func addConnection(_ connection: ServerConnection) {
        connections.append(connection)
    }

    func deleteConnection(at offsets: IndexSet) {
        connections.remove(atOffsets: offsets)
    }

    func updateConnection(_ connection: ServerConnection) {
        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[index] = connection
        }
    }

    private func loadConnections() {
        guard let data = UserDefaults.standard.data(forKey: connectionsKey),
              let decoded = try? JSONDecoder().decode([ServerConnection].self, from: data)
        else { return }
        connections = decoded
    }

    private func saveConnections() {
        guard let data = try? JSONEncoder().encode(connections) else { return }
        UserDefaults.standard.set(data, forKey: connectionsKey)
    }

    private func loadSettings() {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return }
        settings = decoded
    }

    private func saveSettings() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: settingsKey)
    }
}
