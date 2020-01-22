import Foundation
import NIO

public struct Mail {
    public enum ContentType: String {
        case plain = "text/plain"
        case html = "text/html"
    }
    
    public let messageId: String
    public let from: MailUser
    public let to: Set<MailUser>
    public let cc: Set<MailUser>
    public let bcc: Set<MailUser>
    public let subject: String
    public let contentType: ContentType
    public let text: String
    // TODO: Attachments
    
    internal var headers: [String: String] {
        var headers = [String: String]()
        headers.reserveCapacity(16)
        
        headers["Message-Id"] = "<\(UUID().uuidString)@localhost>"
        headers["Date"] = Date().smtpFormatted
        headers["From"] = from.smtpFormatted
        headers["To"] = to.map { $0.smtpFormatted }
            .joined(separator: ", ")

        if !cc.isEmpty {
            headers["Cc"] = cc.map { $0.smtpFormatted }
                .joined(separator: ", ")
        }

        headers["Subject"] = subject
        headers["MIME-Version"] = "1.0"
        headers["Content-Type"] = contentType.rawValue
        
        return headers
    }

//    var headersString: String {
//        return headers.map { (key, value) in
//            return "\(key): \(value)"
//        }.joined(separator: "\r\n")
//    }
}

public struct MailUser: Hashable, ExpressibleByStringLiteral {
    /// The user's name that is displayed in an email. Optional.
    public let name: String?

    /// The user's email address.
    public let email: String
    
    public init(name: String?, email: String) {
        self.name = name
        self.email = email
    }
    
    public init(stringLiteral email: String) {
        self.email = email
        self.name = nil
    }

    var smtpFormatted: String {
        if let name = name {
            return "\(name) <\(email)>"
        } else {
            return "<\(email)>"
        }
    }
}
