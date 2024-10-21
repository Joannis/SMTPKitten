/// A user that can be used in an email. This can be either the sender or a recipient.
public struct MailUser: Hashable, Sendable {
    /// The user's name that is displayed in an email. Optional.
    public let name: String?

    /// The user's email address.
    public let email: String

    /// A new mail user with an optional name.
    public init(name: String? = nil, email: String) {
        self.name = name
        self.email = email
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
