import Foundation

enum ServerPlatform: UInt8, Codable {
    case macOS = 0
    case linux = 1
    case windows = 2
}

struct ServerConnection: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var host: String
    var port: Int = 9877
    var password: String
}

enum InputProtocol: String, Codable, CaseIterable {
    case typeText = "TypeText"
    case keyCode = "KeyCode"
}

struct AppSettings: Codable {
    var sensitivity: Double = 1.0
    var scrollSpeed: Double = 1.0
    var naturalScrolling: Bool = true
    var hapticFeedback: Bool = true
    var clickSound: Bool = true
    var inputProtocol: InputProtocol = .typeText
}
