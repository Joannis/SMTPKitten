enum SMTPClientError: Error {
    case endOfStream
    case protocolError
    case missingHandshake
    case startTLSFailure
    case commandFailed(code: Int)
    case loginFailed
}
