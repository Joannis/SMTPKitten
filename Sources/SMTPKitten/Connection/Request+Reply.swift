import NIOCore

struct SMTPRequest: Sendable {
    let buffer: ByteBuffer
    internal let continuation: CheckedContinuation<SMTPReply, Error>
}

struct SMTPReply: Sendable {
    let code: Int
    var isSuccessful: Bool {
        code < 400
    }
    var isFailed: Bool {
        code >= 400
    }
    let lines: [ByteBuffer]
}

/// The response codes that can be received from the SMTP server.
public enum SMTPCode: Int {
    case serviceReady = 220
    case connectionClosing = 221
    case authSucceeded = 235
    case commandOK = 250
    case willForward = 251
    case containingChallenge = 334
    case startMailInput = 354
    case commandNotRecognized = 502
}

struct SMTPReplyLine: Sendable {
    let code: Int
    let contents: ByteBuffer
    let isLast: Bool
}
