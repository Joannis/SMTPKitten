public protocol SMTPClientRequest {
    var text: String { get }
}

/// Any message that can be sent to the SMTP server.
public enum SMTPClientMessage {
    case none
    case helo(hostname: String)
    case ehlo(hostname: String)
    case starttls
    case authenticatePlain(SMTPPlainCreds)
    case authenticateLogin
    case authenticateCramMd5
    case authenticateXOAuth2(credentials: String)
    case authenticateUser(String)
    case authenticatePassword(String)
    case custom(SMTPClientRequest)
    case quit
    
    case startMail(Mail)
    case mailRecipient(String)
    case startMailData
    case mailData(Mail)
}

/// Any message that can be received from the SMTP server.
public struct SMTPServerMessage {
    var responseCode: SMTPResponseCode? {
        SMTPResponseCode(rawValue: code)
    }
    public let code: Int
    public let lines: [String]
}

/// The response codes that can be received from the SMTP server.
public enum SMTPResponseCode: Int {
    case serviceReady = 220
    case connectionClosing = 221
    case authSucceeded = 235
    case commandOK = 250
    case willForward = 251
    case containingChallenge = 334
    case startMailInput = 354
    case commandNotRecognized = 502
}

/// SMTP Authentication method.
public enum SMTPAuthMethod: String, CaseIterable {
    case plain = "PLAIN"
    case login = "LOGIN"
    case crammd5 = "CRAM-MD5"
    
    var priority: Int {
        switch self {
        case .plain: 0
        case .login: 1
        case .crammd5: 2
        }
    }
}

/// Type for building a correct credentials for PLAIN SMTP auth.
public struct SMTPPlainCreds: SMTPClientRequest {
    public let user: String
    public let password: String
    
    public var text: String {
        "\0\(user)\0\(password)"
    }
}
