enum SMTPError: Error, CustomDebugStringConvertible, CustomStringConvertible {
    case invalidCode(String?)
    case invalidMessage, missingHandshake, incompleteMessage
    case startTlsFailure, starttlsUnsupportedByServer
    case loginFailure
    case disconnected
    case sendMailFailed(Int?)

    var description: String { debugDescription }

    var debugDescription: String {
        switch self {
        case .invalidCode(let code):
            return "Invalid code: \(code ?? "nil")"
        case .invalidMessage:
            return "Invalid message"
        case .missingHandshake:
            return "Missing handshake"
        case .incompleteMessage:
            return "Incomplete message"
        case .startTlsFailure:
            return "STARTTLS failed"
        case .starttlsUnsupportedByServer:
            return "STARTTLS unsupported by server"
        case .loginFailure:
            return "Login failed"
        case .disconnected:
            return "Disconnected"
        case .sendMailFailed(let code):
            return "Send mail failed with code \(code ?? -1)"
        }
    }
}
