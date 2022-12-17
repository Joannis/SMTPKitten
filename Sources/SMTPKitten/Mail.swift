import Foundation
import NIO

/// A mail that can be sent using SMTP. This is the main type that you will be using. It contains all the information that is needed to send an email.
public struct Mail {
    public enum ContentType: String {
        case plain = "text/plain; encoding=utf8"
        case html = "text/html; encoding=utf8"
    }
    
    /// The message ID of the mail. This is automatically generated.
    public let messageId: String

    /// The sender of the mail. This is a `MailUser` struct that contains the name and email address of the sender.
    public var from: MailUser

    /// The recipients of the mail. This is a set of `MailUser` structs that contain the name and email address of the recipients.
    public var to: Set<MailUser>

    /// The carbon copy recipients of the mail. This is a set of `MailUser` structs that contain the name and email address of the recipients.
    public var cc: Set<MailUser>

    /// The blind carbon copy recipients of the mail. This is a set of `MailUser` structs that contain the name and email address of the recipients.
    public var bcc: Set<MailUser>

    /// The subject of the mail.
    public var subject: String

    /// The content type of the mail. This can be either plain text or HTML.
    public var contentType: ContentType

    /// The text of the mail. This can be either plain text or HTML depending on the `contentType` property.
    public var text: String
    
    /// Creates a new `Mail` instance.
    public init(
        from: MailUser,
        to: Set<MailUser>,
        cc: Set<MailUser> = [],
        subject: String,
        contentType: ContentType,
        text: String
    ) {
        self.messageId = UUID().uuidString
        self.from = from
        self.to = to
        self.cc = cc
        self.bcc = []
        self.subject = subject
        self.contentType = contentType
        self.text = text
    }
    // TODO: Attachments
    
    /// Generates the headers of the mail.
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

        if let data = subject.data(using: .utf8) {
            headers["Subject"] = "=?utf-8?B?\(data.base64EncodedString())?="
        } else {
            headers["Subject"] = subject
        }
        headers["MIME-Version"] = "1.0"
        headers["Content-Type"] = contentType.rawValue
        
        return headers
    }
}

/// A user that can be used in an email. This can be either the sender or a recipient.
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

    /// Generates the SMTP formatted string of the user.
    var smtpFormatted: String {
        if let name = name {
            return "\(name) <\(email)>"
        } else {
            return "<\(email)>"
        }
    }
}
