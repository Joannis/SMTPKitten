import Foundation
import NIO

public struct ContentDisposition {
    enum Disposition: String {
        case inline
        case attachment
    }

    let disposition: Disposition

    public static let `inline` = ContentDisposition(disposition: .inline)
    public static let attachment = ContentDisposition(disposition: .attachment)
}

public protocol MailContentConvertible {
    var content: Mail.Content { get }
}

/// A mail that can be sent using SMTP. This is the main type that you will be using. It contains all the information that is needed to send an email.
public struct Mail {
    public struct Content: MailContentConvertible {
        public struct ID: Hashable {
            let id: String

            public init(named name: String = UUID().uuidString) {
                self.id = name
            }
        }

        internal enum Block {
            case plain(String)
            case html(String)
            case image(Mail.Image)
            case attachment(Mail.Attachment)
            case alternative(boundary: String, text: String, html: String)
        }

        internal enum _Content {
            case single(Block)
            case multipart(boundary: String, blocks: [Block])
        }

        internal let _content: _Content
        public var content: Mail.Content { self }

        internal var blocks: [Block] {
            switch _content {
            case .single(let block):
                return [block]
            case .multipart(_, let blocks):
                return blocks
            }
        }

        internal static func single(_ block: Block) -> Content {
            return Content(_content: .single(block))
        }

        internal static func multiple(_ blocks: [Block]) -> Content {
            return Content(_content: .multipart(boundary: UUID().uuidString, blocks: blocks))
        }

        public static func plain(_ text: String) -> Content {
            return .single(.plain(text))
        }

        public static func html(_ html: String) -> Content {
            return .single(.html(html))
        }

        public static func alternative(_ text: String, html: String) -> Content {
            return .single(.alternative(boundary: UUID().uuidString, text: text, html: html))
        }

        public static func alternative(_ blocks: [Content]) -> Content {
            return .multiple(blocks.flatMap(\.blocks))
        }
    }
    
    /// The message ID of the mail. This is automatically generated.
    public let messageId: String

    /// The sender of the mail. This is a `MailUser` struct that contains the name and email address of the sender.
    public var from: MailUser

    /// The reply-to address of the mail. This is a `MailUser` struct that contains the name and email address that replies should be sent to.
    public var replyTo: MailUser?

    /// The recipients of the mail. This is a set of `MailUser` structs that contains the name and email address of the recipients.
    public var to: Set<MailUser>

    /// The carbon copy recipients of the mail. This is a set of `MailUser` structs that contain the name and email address of the recipients.
    public var cc: Set<MailUser>

    /// The blind carbon copy recipients of the mail. This is a set of `MailUser` structs that contain the name and email address of the recipients.
    public var bcc: Set<MailUser>

    /// The subject of the mail.
    public var subject: String

    /// The text of the mail. This can be either plain text or HTML depending on the `contentType` property.
    public var content: Content
    
    /// Creates a new `Mail` instance.
    public init(
        from: MailUser,
        to: Set<MailUser>,
        cc: Set<MailUser> = [],
        subject: String,
        content: Content
    ) {
        self.messageId = UUID().uuidString
        self.from = from
        self.to = to
        self.cc = cc
        self.bcc = []
        self.subject = subject
        self.content = content
    }

    public init(
        from: MailUser,
        to: Set<MailUser>,
        cc: Set<MailUser> = [],
        subject: String,
        @MailBodyBuilder content: () -> Content
    ) {
        self.messageId = UUID().uuidString
        self.from = from
        self.to = to
        self.cc = cc
        self.bcc = []
        self.subject = subject
        self.content = content()
    }

    // TODO: Attachments
    
    /// Generates the headers of the mail.
    internal var headers: [String: String] {
        var headers = content.headers
        headers.reserveCapacity(16)

        headers["MIME-Version"] = "1.0"
        headers["Message-Id"] = "<\(UUID().uuidString)@localhost>"
        headers["Date"] = Date().smtpFormatted
        headers["From"] = from.smtpFormatted
        headers["To"] = to.map { $0.smtpFormatted }
            .joined(separator: ", ")

        if let replyTo {
            headers["Reply-To"] = replyTo.smtpFormatted
        }

        if !cc.isEmpty {
            headers["Cc"] = cc.map { $0.smtpFormatted }
                .joined(separator: ", ")
        }

        if let data = subject.data(using: .utf8) {
            headers["Subject"] = "=?utf-8?B?\(data.base64EncodedString())?="
        } else {
            headers["Subject"] = subject
        }
        
        return headers
    }
}

extension Mail.Content {
    internal var headers: [String: String] {
        switch _content {
        case .single(let block):
            return block.headers
        case .multipart(boundary: let boundary, blocks: _):
            return [
                "Content-Type": "multipart/mixed; boundary=\(boundary)",
            ]
        }
    }

    @discardableResult
    internal func writePayload(into buffer: inout ByteBuffer) -> Int {
        switch _content {
        case .multipart(boundary: let boundary, blocks: let blocks):
            var written = 0
            for block in blocks {
                let headers = block.headers.map { "\($0): \($1)" }.joined(separator: "\r\n")
                written += buffer.writeString("""
                --\(boundary)
                \(headers)


                """)

                written += block.writePayload(into: &buffer)
                written += buffer.writeString("\n")
            }

            return written
        case .single(let block):
            return block.writePayload(into: &buffer)
        }
    }
}

extension Mail {
    public struct Image: MailContentConvertible {
        let mime: String
        let base64: String
        let filename: String?
        let contentDisposition: ContentDisposition
        let contentId: Content.ID

        public var content: Mail.Content { .single(.image(self)) }

        public static func png(
            _ buffer: Data,
            filename: String? = nil,
            contentDisposition: ContentDisposition = .inline,
            contentId: Content.ID = .init()
        ) -> Image {
            return Image(
                mime: "image/png",
                base64: buffer.base64EncodedString(),
                filename: filename,
                contentDisposition: contentDisposition,
                contentId: contentId
            )
        }

        public static func jpeg(
            _ buffer: Data,
            filename: String? = nil,
            contentDisposition: ContentDisposition = .inline,
            contentId: Content.ID = .init()
        ) -> Image {
            return Image(
                mime: "image/jpeg",
                base64: buffer.base64EncodedString(),
                filename: filename,
                contentDisposition: contentDisposition,
                contentId: contentId
            )
        }
    }
}

extension Mail {
    public struct Attachment: MailContentConvertible {
        let mime: String
        let base64: String
        let filename: String?
        let contentDisposition: ContentDisposition

        public var content: Mail.Content { .single(.attachment(self)) }

        public init(
            _ buffer: Data,
            mimeType mime: String,
            filename: String? = nil,
            contentDisposition: ContentDisposition = .inline
        ) {
            self.mime = mime
            self.base64 = buffer.base64EncodedString()
            self.filename = filename
            self.contentDisposition = contentDisposition
        }
    }
}

extension String: MailContentConvertible {
    public var content: Mail.Content {
        .plain(self)
    }
}

extension Mail.Content.Block {
    var headers: [String: String] {
        switch self {
        case .plain:
            return [
                "Content-Type": "text/plain; charset=utf-8",
            ]
        case .html:
            return [
                "Content-Type": "text/html; charset=utf-8",
            ]
        case .alternative(let boundary, _, _):
            return [
                "Content-Type": "multipart/alternative; boundary=\(boundary)",
            ]
        case .image(let image):
            var disposition = image.contentDisposition.disposition.rawValue

            if let filename = image.filename {
                disposition += "; filename=\"\(filename)\""
            }
            
            return [
                "Content-Type": image.mime,
                "Content-Disposition": disposition,
                "Content-ID": image.contentId.id,
                "Content-Transfer-Encoding": "base64",
            ]
        case .attachment(let attachment):
            var disposition = attachment.contentDisposition.disposition.rawValue

            if let filename = attachment.filename {
                disposition += "; filename=\"\(filename)\""
            }

            return [
                "Content-Type": attachment.mime,
                "Content-Disposition": disposition,
                "Content-Transfer-Encoding": "base64",
            ]
        }
    }

    @discardableResult
    internal func writePayload(into buffer: inout ByteBuffer) -> Int {
        switch self {
        case .plain(let text):
            return buffer.writeString(text)
        case .html(let html):
            return buffer.writeString(html)
        case .alternative(let boundary, let text, let html):
            return buffer.writeString("""
            --\(boundary)
            Content-Type: text/plain; charset=utf-8\r
            Content-Transfer-Encoding: 8BIT\r

            \(text)
            --\(boundary)
            Content-Type: text/html; charset=utf-8
            Content-Transfer-Encoding: 8BIT

            \(html)
            --\(boundary)--
            """)
        case .image(let image):
            return buffer.writeString(image.base64)
        case .attachment(let attachment):
            return buffer.writeString(attachment.base64)
        }
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
