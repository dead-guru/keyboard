import SwiftUI

struct ConnectionsView: View {
    @Bindable var appState: AppState
    @State private var showAddSheet = false
    @State private var editingConnection: ServerConnection?
    @State private var connectingId: UUID?

    var body: some View {
        Group {
            if appState.connections.isEmpty {
                emptyState
            } else {
                connectionsList
            }
        }
        .navigationTitle("Servers")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            ConnectionFormView(title: "Add Server") { connection in
                appState.addConnection(connection)
            }
        }
        .sheet(item: $editingConnection) { connection in
            ConnectionFormView(title: "Edit Server", connection: connection) { updated in
                appState.updateConnection(updated)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Servers", systemImage: "server.rack")
        } description: {
            Text("Add a server to get started.")
        } actions: {
            Button("Add Server") {
                showAddSheet = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var connectionsList: some View {
        List {
            ForEach(appState.connections) { connection in
                ConnectionRow(
                    connection: connection,
                    isConnecting: connectingId == connection.id,
                    onConnect: { connectTo(connection) },
                    onEdit: { editingConnection = connection }
                )
            }
            .onDelete { offsets in
                appState.deleteConnection(at: offsets)
            }

            if let error = appState.connectionError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func connectTo(_ connection: ServerConnection) {
        connectingId = connection.id
        Task {
            await appState.connect(to: connection)
            connectingId = nil
        }
    }
}

private struct ConnectionRow: View {
    let connection: ServerConnection
    let isConnecting: Bool
    let onConnect: () -> Void
    let onEdit: () -> Void

    var body: some View {
        Button(action: onConnect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(connection.name)
                        .font(.headline)
                    Text("\(connection.host):\(connection.port)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isConnecting {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.right.circle")
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onEdit()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
        }
    }
}

struct ConnectionFormView: View {
    let title: String
    var connection: ServerConnection?
    let onSave: (ServerConnection) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var host = ""
    @State private var port = "9877"
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                    TextField("Host (IP or hostname)", text: $host)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("Port", text: $port)
                        .keyboardType(.numberPad)
                }
                Section("Authentication") {
                    SecureField("Password", text: $password)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let portNum = Int(port) ?? 9877
                        var conn = connection ?? ServerConnection(name: name, host: host, port: portNum, password: password)
                        if connection != nil {
                            conn.name = name
                            conn.host = host
                            conn.port = portNum
                            conn.password = password
                        }
                        onSave(conn)
                        dismiss()
                    }
                    .disabled(name.isEmpty || host.isEmpty)
                }
            }
            .onAppear {
                if let connection {
                    name = connection.name
                    host = connection.host
                    port = String(connection.port)
                    password = connection.password
                }
            }
        }
    }
}
