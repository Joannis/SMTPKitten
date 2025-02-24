import Foundation

internal struct SMTPHandshake {
    enum KnownCapability {
        case startTLS
        case mime8bit
        case pipelining
        case pipeconnect
        case login
        case loginPlain
    }

    var capabilities = Set<KnownCapability>()

    init(_ message: SMTPReply) {
        for line in message.lines {
            let line = String(buffer: line)

            switch line {
            case "STARTTLS":
                capabilities.insert(.startTLS)
            case "8BITMIME":
                capabilities.insert(.mime8bit)
            case "PIPELINING":
                capabilities.insert(.pipelining)
            case "PIPECONNECT":
                capabilities.insert(.pipeconnect)
            case let auth where auth.hasPrefix("LOGIN"):
                for method in auth.split(separator: " ").dropFirst() {
                    switch method {
                    case "PLAIN":
                        capabilities.insert(.loginPlain)
                    case "LOGIN":
                        capabilities.insert(.login)
                    default:
                        ()
                    }
                }
            default:
                ()
            }
        }
    }
}

extension SMTPConnection.Handle {
    internal func handshake(hostname: String) async throws -> SMTPHandshake {
        var message = try await send(.ehlo(hostname: hostname))
        if message.isSuccessful {
            return SMTPHandshake(message)
        }

        message = try await self.send(.helo(hostname: hostname))
        return SMTPHandshake(message)
    }
}
