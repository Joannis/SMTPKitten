extension SMTPClient {
    public func login(user: String, password: String) async throws {
        try await send(.authenticateLogin)
            .status(.containingChallenge, or: SMTPClientError.loginFailed)

        try await send(.authenticateUser(user))
            .status(.containingChallenge, or: SMTPClientError.loginFailed)

        try await self.send(.authenticatePassword(password))
            .status(.authSucceeded, or: SMTPClientError.loginFailed)
    }
}
