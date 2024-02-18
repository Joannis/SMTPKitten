import Foundation

/// A mail that can be sent using SMTP. This is the main type that you will be using. It contains all the information that is needed to send an email.
public struct Mail: Sendable {
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
}
