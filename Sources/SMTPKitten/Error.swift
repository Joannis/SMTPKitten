enum SMTPError: Error {
    case invalidCode(String?)
    case invalidMessage, missingHandshake, incompleteMessage
    case startTlsFailure, starttlsUnsupportedByServer
    case loginFailure
    case disconnected
    case sendMailFailed(SMTPResponseCode?)
}
