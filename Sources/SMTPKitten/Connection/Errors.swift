enum SMTPConnectionError: Error {
    case endOfStream
    case protocolError
    case startTLSFailure
    case commandFailed(code: Int)
    case loginFailed
}
