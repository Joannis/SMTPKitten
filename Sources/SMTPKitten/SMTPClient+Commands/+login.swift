extension SMTPClient.Handle {
    internal func selectAuthMethod() -> SMTPAuthMethod {
        if handshake.capabilities.contains(.loginPlain) {
            return .plain
        } else {
            return .login
        }
    }

    public func login(
        user: String,
        password: String,
        method: SMTPAuthMethod? = nil
    ) async throws {
        let method = method ?? selectAuthMethod()

        switch method.method {
        case .login:
            try await send(.authenticateLogin)
                .status(.containingChallenge, or: SMTPClientError.loginFailed)

            try await send(.authenticateUser(user))
                .status(.containingChallenge, or: SMTPClientError.loginFailed)

            try await self.send(.authenticatePassword(password))
                .status(.authSucceeded, or: SMTPClientError.loginFailed)
        case .plain:
            try await send(.authenticatePlain(
                credentials: .init(user: user, password: password))
            )
            .status(.authSucceeded, or: SMTPClientError.loginFailed)
        }
    }
}
