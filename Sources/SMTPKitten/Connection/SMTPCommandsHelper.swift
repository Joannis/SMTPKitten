import NIOCore

enum SMTPCredentials {
    struct Plain {
        let user: String
        let password: String

        var text: String {
            "\0\(user)\0\(password)"
        }
    }
}

/// SMTP Authentication method.
public struct SMTPAuthMethod {
    internal enum _Method: String, CaseIterable {
        case plain = "PLAIN"
        case login = "LOGIN"
    }

    let method: _Method

    public static let login = SMTPAuthMethod(method: .login)
    public static let plain = SMTPAuthMethod(method: .plain)
}

enum _SMTPRequest: Sendable {
    case helo(hostname: String)
    case ehlo(hostname: String)
    case starttls
    case authenticatePlain(credentials: SMTPCredentials.Plain)
    case authenticateLogin
    case authenticateCramMd5
    case authenticateXOAuth2(credentials: String)
    case authenticateUser(String)
    case authenticatePassword(String)
    case quit

    case startMail(Mail)
    case mailRecipient(String)
    case startMailData
    case mailData(Mail)

    func write(into out: inout ByteBuffer) {
        switch self {
        case .helo(let hostname):
            out.writeString("HELO ")
            out.writeString(hostname)
        case .ehlo(let hostname):
            out.writeString("EHLO ")
            out.writeString(hostname)
        case .startMail(let mail):
            out.writeString("MAIL FROM: <\(mail.from.email)> BODY=8BITMIME")
        case .mailRecipient(let address):
            out.writeString("RCPT TO: <\(address)>")
        case .startMailData:
            out.writeString("DATA")
        case .mailData(let mail):
            var headersText = ""
            for header in mail.headers {
                headersText += "\(header.key): \(header.value)\r\n"
            }
            headersText += "Content-Transfer-Encoding: 7bit\r\n"
            out.writeString(headersText)
            out.writeString("\r\n")
            mail.content.writePayload(into: &out)
            out.writeString("\r\n.")
        case .starttls:
            out.writeString("STARTTLS")
        case .authenticatePlain(let credentials):
            out.writeString("AUTH PLAIN \(credentials.text.base64Encoded)")
        case .authenticateLogin:
            out.writeString("AUTH LOGIN")
        case .authenticateCramMd5:
            out.writeString("AUTH CRAM-MD5")
        case .authenticateXOAuth2(let credentials):
            out.writeString("AUTH XOAUTH2 ")
            out.writeString(credentials)
        case .authenticateUser(let user):
            out.writeString(user.base64Encoded)
        case .authenticatePassword(let password):
            out.writeString(password.base64Encoded)
        case .quit:
            out.writeString("QUIT")
        }

        out.writeInteger(cr)
        out.writeInteger(lf)
    }
}

extension SMTPClient {
    func send(_ request: _SMTPRequest) async throws -> SMTPReply {
        var buffer = channel.channel.allocator.buffer(capacity: 4096)
        request.write(into: &buffer)
        return try await send(buffer)
    }
}
