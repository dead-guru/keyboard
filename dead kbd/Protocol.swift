import Foundation

enum MessageType: UInt8 {
    case authRequest = 0x01
    case authResponse = 0x02
    case mouseMove = 0x03
    case mouseButton = 0x04
    case scroll = 0x05
    case keyEvent = 0x06
    case ping = 0x07
    case pong = 0x08
    case platformInfo = 0x09
    case typeText = 0x0A
}

enum MouseButton: UInt8 {
    case left = 0
    case right = 1
    case middle = 2
}

enum ProtocolEncoder {
    static func authRequest(password: String) -> Data {
        let passwordData = Data(password.utf8)
        var data = Data([MessageType.authRequest.rawValue])
        var len = UInt16(passwordData.count).bigEndian
        data.append(Data(bytes: &len, count: 2))
        data.append(passwordData)
        return data
    }

    static func mouseMove(dx: Float, dy: Float) -> Data {
        var data = Data([MessageType.mouseMove.rawValue])
        var beDx = dx.bitPattern.bigEndian
        var beDy = dy.bitPattern.bigEndian
        data.append(Data(bytes: &beDx, count: 4))
        data.append(Data(bytes: &beDy, count: 4))
        return data
    }

    static func mouseButton(_ button: MouseButton, pressed: Bool) -> Data {
        Data([MessageType.mouseButton.rawValue, button.rawValue, pressed ? 1 : 0])
    }

    static func scroll(dx: Float, dy: Float) -> Data {
        var data = Data([MessageType.scroll.rawValue])
        var beDx = dx.bitPattern.bigEndian
        var beDy = dy.bitPattern.bigEndian
        data.append(Data(bytes: &beDx, count: 4))
        data.append(Data(bytes: &beDy, count: 4))
        return data
    }

    static func keyEvent(keyCode: UInt16, pressed: Bool) -> Data {
        var data = Data([MessageType.keyEvent.rawValue])
        var beKey = keyCode.bigEndian
        data.append(Data(bytes: &beKey, count: 2))
        data.append(pressed ? 1 : 0)
        return data
    }

    static func typeText(_ text: String) -> Data {
        let textData = Data(text.utf8)
        var data = Data([MessageType.typeText.rawValue])
        var len = UInt16(textData.count).bigEndian
        data.append(Data(bytes: &len, count: 2))
        data.append(textData)
        return data
    }

    static func ping() -> Data {
        Data([MessageType.ping.rawValue])
    }
}

enum ProtocolDecoder {
    struct AuthResponse {
        let success: Bool
    }

    static func decode(_ data: Data) -> Any? {
        guard let first = data.first, let type = MessageType(rawValue: first) else { return nil }
        switch type {
        case .authResponse:
            guard data.count >= 2 else { return nil }
            return AuthResponse(success: data[1] == 1)
        case .platformInfo:
            guard data.count >= 2 else { return nil }
            return ServerPlatform(rawValue: data[1])
        case .pong:
            return MessageType.pong
        default:
            return nil
        }
    }
}
