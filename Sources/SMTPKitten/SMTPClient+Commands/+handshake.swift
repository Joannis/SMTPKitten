import Foundation

internal struct SMTPHandshake {
    let starttls: Bool

    init?(_ message: SMTPReply) {
        guard SMTPCode(rawValue: message.code) == .commandOK else {
            return nil
        }

        var starttls = false

        for var line in message.lines {
            if let string = line.readString(length: line.readableBytes) {
                let capability = string.uppercased()

                if capability == "STARTTLS" {
                    starttls = true
                }
            }
        }

        self.starttls = starttls
    }
}

extension SMTPClient {
    internal func handshake(hostname: String) async throws -> SMTPHandshake {
        var message = try await send(.ehlo(hostname: hostname))
        if let handshake = SMTPHandshake(message) {
            return handshake
        }

        message = try await self.send(.helo(hostname: hostname))
        guard let handshake = SMTPHandshake(message) else {
            throw SMTPClientError.missingHandshake
        }

        return handshake
    }
}
