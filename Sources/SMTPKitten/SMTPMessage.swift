public protocol SMTPClientRequest {
    var text: String { get }
}

public enum SMTPClientMessage {
    case none
    case helo(hostname: String)
    case ehlo(hostname: String)
    case starttls
    case authenticatePlain
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

public struct SMTPServerMessage {
    var responseCode: SMTPResponseCode? {
        SMTPResponseCode(rawValue: code)
    }
    let code: Int
    let message: String
}

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
