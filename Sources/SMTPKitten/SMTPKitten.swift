import NIO
import NIOSSL

public enum SMTPSSLConfiguration {
    case `default`
    case customRoot(path: String)
    
    internal func makeTlsConfiguration() -> TLSConfiguration {
        switch self {
        case .default:
            return TLSConfiguration.makeClientConfiguration()
        case .customRoot(let path):
            var configuration = TLSConfiguration.makeClientConfiguration()
            configuration.certificateVerification = .fullVerification
            configuration.trustRoots = .file(path)
            return configuration
        }
    }
}

public enum SMTPSSLMode {
    case startTLS(configuration: SMTPSSLConfiguration)
    case tls(configuration: SMTPSSLConfiguration)
    case insecure
}

private struct OutstandingRequest {
    let promise: EventLoopPromise<[SMTPServerMessage]>
    let sendMessage: () -> EventLoopFuture<Void>
}

internal final class SMTPClientContext {
    private var queue = [OutstandingRequest]()
    private var isProcessing = false
    let eventLoop: EventLoop
    
    init(eventLoop: EventLoop) {
        self.eventLoop = eventLoop
    }
    
    private func _sendMessage(
        sendMessage: @escaping () -> EventLoopFuture<Void>
    ) -> EventLoopFuture<[SMTPServerMessage]> {
        eventLoop.flatSubmit {
            let item = OutstandingRequest(
                promise: self.eventLoop.makePromise(),
                sendMessage: sendMessage
            )
            
            self.queue.append(item)
            
            self.processNext()
            
            return item.promise.futureResult
        }
    }
    
    func sendMessage(messages: @escaping () -> EventLoopFuture<Void>) async throws -> [SMTPServerMessage] {
        return try await withCheckedThrowingContinuation({ continuation in
            _sendMessage(sendMessage: messages).whenComplete { result in
                do {
                    continuation.resume(returning: try result.get())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        })
    }
    
    func receive(_ messages: [SMTPServerMessage]) {
        self.queue.first?.promise.succeed(messages)
    }
    
    func disconnect() {
        for request in queue {
            request.promise.fail(SMTPError.disconnected)
        }
    }
    
    private func processNext() {
        guard !isProcessing, let item = queue.first else {
            return
        }
        
        // Start 'em back up again
        item.sendMessage().flatMap {
            item.promise.futureResult
        }.hop(to: eventLoop).whenComplete { _ in
            // Ensure this item it out of the pool
            self.queue.removeFirst()
            self.isProcessing = false
            
            self.processNext()
        }
    }
    
    deinit {
        disconnect()
    }
}

internal struct SMTPHandshake {
    let starttls: Bool
    
    init?(_ messages: [SMTPServerMessage]) {
        guard messages.count > 0, messages[0].responseCode == .commandOK else {
            return nil
        }
        
        var starttls = false
        
        for message in messages {
            let capability = message.message.uppercased()
            
            if capability == "STARTTLS" {
                starttls = true
            }
        }
        
        self.starttls = starttls
    }
}

public final class SMTPClient {
    private let channel: Channel
    public let eventLoop: EventLoop
    private let context: SMTPClientContext
    public let hostname: String
    
    internal private(set) var handshake: SMTPHandshake?
    
    init(
        channel: Channel,
        eventLoop: EventLoop,
        context: SMTPClientContext,
        hostname: String
    ) {
        self.channel = channel
        self.eventLoop = eventLoop
        self.context = context
        self.hostname = hostname
    }
    
    public static func connect(
        hostname: String,
        port: Int = 587,
        ssl: SMTPSSLMode
    ) async throws -> SMTPClient {
        let eventLoop = MultiThreadedEventLoopGroup(numberOfThreads: 1).next()
        return try await connect(hostname: hostname, port: port, ssl: ssl, eventLoop: eventLoop)
    }
    
    public static func connect(
        hostname: String,
        port: Int = 587,
        ssl: SMTPSSLMode,
        eventLoop: EventLoop
    ) async throws -> SMTPClient {
        let context = SMTPClientContext(eventLoop: eventLoop)
        
        let client = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SMTPClient, Error>) in
            ClientBootstrap(group: eventLoop).channelInitializer { channel in
                let parser = ByteToMessageHandler(SMTPClientInboundHandler(context: context))
                let serializer = MessageToByteHandler(SMTPClientOutboundHandler())
                var handlers: [ChannelHandler] = [parser, serializer]
                
                switch ssl {
                case .insecure, .startTLS:
                    break
                case let .tls(configuration):
                    do {
                        let sslContext = try NIOSSLContext(configuration: configuration.makeTlsConfiguration())
                        let sslHandler = try NIOSSLClientHandler(context: sslContext, serverHostname: hostname)
                        
                        handlers.insert(sslHandler, at: 0)
                    } catch {
                        return eventLoop.makeFailedFuture(error)
                    }
                }
                
                return channel.pipeline.addHandlers(handlers)
            }.connect(host: hostname, port: port).whenComplete({ result in
                do {
                    let channel = try result.get()
                    continuation.resume(returning: SMTPClient(
                        channel: channel,
                        eventLoop: eventLoop,
                        context: context,
                        hostname: hostname
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            })
        }
        
        let _ = try await client.send(.none)
        let handshake = try await client.doHandshake()
        
        if case .startTLS(let configuration) = ssl {
            if !handshake.starttls {
                throw SMTPError.starttlsUnsupportedByServer
            }
            
            try await client.starttls(configuration: configuration)
            let tlsHandshake = try await client.doHandshake()
            client.handshake = tlsHandshake
        }
        
        return client
    }
    
    public func send(
        _ message: SMTPClientMessage
    ) async throws -> [SMTPServerMessage] {
        try await context.sendMessage {
            return self.channel.writeAndFlush(message)
        }
    }
    
    public func sendWithoutResponse(
        _ message: SMTPClientMessage
    ) -> EventLoopFuture<Void> {
        return self.channel.writeAndFlush(message)
    }
    
    internal func doHandshake() async throws-> SMTPHandshake {
        let ehloMessages = try await send(.ehlo(hostname: hostname))
        
        if let handshake = SMTPHandshake(ehloMessages) {
            return handshake
        }
        
        let heloMessages = try await send(.helo(hostname: hostname))
        
        guard let handshake = SMTPHandshake(heloMessages) else {
            throw SMTPError.missingHandshake
        }
        
        return handshake
    }
    
    internal func starttls(configuration: SMTPSSLConfiguration) async throws {
        let messages = try await send(.starttls)
        
        guard messages.first?.responseCode == .serviceReady else {
            throw SMTPError.startTlsFailure
        }
        
        do {
            let sslContext = try NIOSSLContext(configuration: configuration.makeTlsConfiguration())
            let sslHandler = try NIOSSLClientHandler(context: sslContext, serverHostname: self.hostname)
            
            try await self.channel.pipeline.addHandler(sslHandler, position: .first)
        } catch {
            throw error
        }
    }
    
    public func login(user: String, password: String) async throws {
        guard try await send(.authenticateLogin).first?.responseCode == .containingChallenge else {
            throw SMTPError.loginFailure
        }
                
        guard try await send(.authenticateUser(user)).first?.responseCode == .containingChallenge else {
            throw SMTPError.loginFailure
        }
                
        guard try await send(.authenticatePassword(password)).first?.responseCode == .authSucceeded else {
            throw SMTPError.loginFailure
        }
    }
    
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
                
        try await send(.startMail(mail)).status(.commandOK)
        
        try await withThrowingTaskGroup(of: Void.self, body: { group in
            for address in recipients {
                group.addTask {
                    return try await self.send(.mailRecipient(address.email)).status(.commandOK, .willForward)
                }
            }
        })
        
        try await send(.startMailData).status(.startMailInput)
        try await send(.mailData(mail)).status(.commandOK)
    }
}

extension Array where Element == SMTPServerMessage {
    func status(_ status: SMTPResponseCode...) throws {
        guard let currentStatus = self.first?.responseCode else {
            throw SMTPError.sendMailFailed
        }
        
        for neededStatus in status {
            if currentStatus == neededStatus {
                return
            }
        }
        
        throw SMTPError.sendMailFailed
    }
}
