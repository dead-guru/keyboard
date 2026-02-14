import Foundation

@Observable
final class WebSocketClient {
    var isConnected = false
    var connectionError: String?
    var platform: ServerPlatform = .macOS

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var pingTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var authContinuation: CheckedContinuation<Bool, Never>?
    private var platformContinuation: CheckedContinuation<ServerPlatform?, Never>?
    private var lastPongTime: Date = .now
    private var awaitingPong = false

    func connect(to server: ServerConnection) async -> Bool {
        disconnect()

        guard let url = URL(string: "ws://\(server.host):\(server.port)") else {
            connectionError = "Invalid server address"
            return false
        }

        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 5
        session = URLSession(configuration: config)
        let task = session!.webSocketTask(with: url)
        webSocketTask = task
        task.resume()

        startReceiving()

        let authData = ProtocolEncoder.authRequest(password: server.password)
        do {
            try await task.send(.data(authData))
        } catch {
            connectionError = "Failed to send auth: \(error.localizedDescription)"
            disconnect()
            return false
        }

        let success = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            self.authContinuation = continuation

            Task {
                try? await Task.sleep(for: .seconds(5))
                if let c = self.authContinuation {
                    self.authContinuation = nil
                    c.resume(returning: false)
                }
            }
        }

        if success {
            // Wait for PlatformInfo message (with timeout)
            let receivedPlatform = await withCheckedContinuation { (continuation: CheckedContinuation<ServerPlatform?, Never>) in
                self.platformContinuation = continuation

                Task {
                    try? await Task.sleep(for: .seconds(3))
                    if let c = self.platformContinuation {
                        self.platformContinuation = nil
                        c.resume(returning: nil)
                    }
                }
            }

            platform = receivedPlatform ?? .macOS
            isConnected = true
            connectionError = nil
            lastPongTime = .now
            awaitingPong = false
            startPing()
            return true
        } else {
            if connectionError == nil {
                connectionError = "Authentication failed"
            }
            disconnect()
            return false
        }
    }

    func disconnect() {
        pingTask?.cancel()
        pingTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        session?.invalidateAndCancel()
        session = nil
        isConnected = false
    }

    func sendMouseMove(dx: Float, dy: Float) {
        send(ProtocolEncoder.mouseMove(dx: dx, dy: dy))
    }

    func sendMouseButton(_ button: MouseButton, pressed: Bool) {
        send(ProtocolEncoder.mouseButton(button, pressed: pressed))
    }

    func sendScroll(dx: Float, dy: Float) {
        send(ProtocolEncoder.scroll(dx: dx, dy: dy))
    }

    func sendKeyEvent(keyCode: UInt16, pressed: Bool) {
        send(ProtocolEncoder.keyEvent(keyCode: keyCode, pressed: pressed))
    }

    func sendTypeText(_ text: String) {
        send(ProtocolEncoder.typeText(text))
    }

    private func send(_ data: Data) {
        webSocketTask?.send(.data(data)) { _ in }
    }

    private func startReceiving() {
        receiveTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                guard let task = self.webSocketTask else { break }
                do {
                    let message = try await task.receive()
                    switch message {
                    case .data(let data):
                        self.handleMessage(data)
                    case .string(let string):
                        if let data = string.data(using: .utf8) {
                            self.handleMessage(data)
                        }
                    @unknown default:
                        break
                    }
                } catch {
                    if !Task.isCancelled {
                        await MainActor.run {
                            self.connectionError = "Connection lost"
                            self.isConnected = false
                        }
                    }
                    break
                }
            }
        }
    }

    private func handleMessage(_ data: Data) {
        guard let decoded = ProtocolDecoder.decode(data) else { return }
        if let auth = decoded as? ProtocolDecoder.AuthResponse {
            if let c = authContinuation {
                authContinuation = nil
                c.resume(returning: auth.success)
            }
        } else if let serverPlatform = decoded as? ServerPlatform {
            if let c = platformContinuation {
                platformContinuation = nil
                c.resume(returning: serverPlatform)
            }
        } else if let msgType = decoded as? MessageType, msgType == .pong {
            lastPongTime = .now
            awaitingPong = false
        }
    }

    private func startPing() {
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self, let task = self.webSocketTask else { break }

                // Check if previous pong timed out
                if self.awaitingPong && Date.now.timeIntervalSince(self.lastPongTime) > 10 {
                    await MainActor.run {
                        self.connectionError = "Connection timed out"
                        self.isConnected = false
                    }
                    break
                }

                self.awaitingPong = true
                let data = ProtocolEncoder.ping()
                try? await task.send(.data(data))
            }
        }
    }
}
