extension SMTPClient {
    public func sendMail(_ mail: Mail) async throws {
        var recipients = [MailUser]()

        for user in mail.to {
            recipients.append(user)
        }

        for user in mail.cc {
            recipients.append(user)
        }

        for user in mail.bcc {
            recipients.append(user)
        }

        try await send(.startMail(mail))
            .status(.commandOK)

        for address in recipients {
            try await send(.mailRecipient(address.email))
                .status(.commandOK, .willForward)
        }

        try await send(.startMailData)
            .status(.startMailInput)

        try await send(.mailData(mail))
            .status(.commandOK)
    }
}
