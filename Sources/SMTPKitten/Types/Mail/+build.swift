extension Mail {
    public static func build(
        from: MailUser,
        to: Set<MailUser>,
        cc: Set<MailUser> = [],
        subject: String,
        @MailBodyBuilder content: () throws -> Content
    ) rethrows -> Mail {
        try Mail(
            from: from,
            to: to,
            cc: cc,
            subject: subject,
            content: content()
        )
    }
}
