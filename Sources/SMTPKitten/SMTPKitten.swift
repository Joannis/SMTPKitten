import NIO
import NIOSSL

public enum SMTPSSLConfiguration {
    case `default`
    case customRoot(path: String)
    case custom(TLSConfiguration)
    
    internal func makeTlsConfiguration() -> TLSConfiguration {
        switch self {
        case .default:
            return TLSConfiguration.clientDefault
        case .customRoot(let path):
            var tlsConfig = TLSConfiguration.makeClientConfiguration()
            tlsConfig.trustRoots = .file(path)
            return tlsConfig
        case .custom(let config):
            return config
        }
    }
}

/// The mode that the SMTP client should use for SSL. This can be either `startTLS`, `tls` or `insecure`.
public enum SMTPSSLMode {
    /// The SMTP client should use the `STARTTLS` command to upgrade the connection to SSL.
    case startTLS(configuration: SMTPSSLConfiguration)

    /// The SMTP client should use SSL from the start.
    case tls(configuration: SMTPSSLConfiguration)

    /// The SMTP client should not use SSL.
    case insecure
}

private struct OutstandingRequest {
    let promise: EventLoopPromise<[SMTPServerMessage]>
    let sendMessage: () -> EventLoopFuture<Void>
}

internal final class ErrorCloseHandler: ChannelInboundHandler {
    typealias InboundIn = NIOAny
    
    init() {}
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.fireErrorCaught(error)
        context.close(promise: nil)
    }
}


internal final class SMTPClientContext {
    private var queue = [OutstandingRequest]()
    private var isProcessing = false
    let eventLoop: EventLoop
    
    init(eventLoop: EventLoop) {
        self.eventLoop = eventLoop
    }
    
    func sendMessage(
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

/// The SMTP client. This is the main entry point for the SMTPKitten library. It is used to connect to an SMTP server and send emails.
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
    
    /// Connect to an SMTP server.
    public static func connect(
        hostname: String,
        port: Int = 587,
        ssl: SMTPSSLMode
    ) -> EventLoopFuture<SMTPClient> {
        let eventLoop = MultiThreadedEventLoopGroup(numberOfThreads: 1).next()
        return connect(hostname: hostname, port: port, ssl: ssl, eventLoop: eventLoop)
    }
    
    /// Connect to an SMTP server.
    public static func connect(
        hostname: String,
        channel: Channel,
        ssl: SMTPSSLMode
    ) -> EventLoopFuture<SMTPClient> {
        let context = SMTPClientContext(eventLoop: channel.eventLoop)
        
        let parser = ByteToMessageHandler(SMTPClientInboundHandler(context: context))
        let serializer = MessageToByteHandler(SMTPClientOutboundHandler())
        var handlers: [ChannelHandler] = [parser, serializer, ErrorCloseHandler()]
        
        switch ssl {
        case .insecure, .startTLS:
            break
        case let .tls(configuration):
            do {
                let sslContext = try NIOSSLContext(configuration: configuration.makeTlsConfiguration())
                let sslHandler = try NIOSSLClientHandler(context: sslContext, serverHostname: hostname)
                
                handlers.insert(sslHandler, at: 0)
            } catch {
                return channel.eventLoop.makeFailedFuture(error)
            }
        }
        
        return channel.pipeline.addHandlers(handlers).map {
            return SMTPClient(
                channel: channel,
                eventLoop: channel.eventLoop,
                context: context,
                hostname: hostname
            )
        }.flatMap { client in
            client.send(.none).flatMap { response in
                client.doHandshake()
            }.flatMap { handshake in
                client.handshake = handshake
                
                if case .startTLS(let configuration) = ssl {
                    if !handshake.starttls {
                        return channel.eventLoop.makeFailedFuture(SMTPError.starttlsUnsupportedByServer)
                    }
                    
                    return client.starttls(configuration: configuration).flatMap {
                        return client.doHandshake()
                    }.map { handshake in
                        client.handshake = handshake
                        return client
                    }
                }
                
                return channel.eventLoop.makeSucceededFuture(client)
            }
        }
    }
        
    /// Connect to an SMTP server.
    public static func connect(
        hostname: String,
        port: Int = 587,
        ssl: SMTPSSLMode,
        eventLoop: EventLoop
    ) -> EventLoopFuture<SMTPClient> {
        let context = SMTPClientContext(eventLoop: eventLoop)
        
        return ClientBootstrap(group: eventLoop).channelInitializer { channel in
            let parser = ByteToMessageHandler(SMTPClientInboundHandler(context: context))
            let serializer = MessageToByteHandler(SMTPClientOutboundHandler())
            var handlers: [ChannelHandler] = [parser, serializer, ErrorCloseHandler()]
            
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
        }.connect(host: hostname, port: port).map { channel in
            return SMTPClient(
                channel: channel,
                eventLoop: eventLoop,
                context: context,
                hostname: hostname
            )
        }.flatMap { client in
            client.send(.none).flatMap { response in
                client.doHandshake()
            }.flatMap { handshake in
                client.handshake = handshake
                
                if case .startTLS(let configuration) = ssl {
                    if !handshake.starttls {
                        return eventLoop.makeFailedFuture(SMTPError.starttlsUnsupportedByServer)
                    }
                    
                    return client.starttls(configuration: configuration)
                        .flatMap(client.doHandshake)
                        .map { handshake in
                            client.handshake = handshake
                            return client
                        }
                }
                
                return eventLoop.makeSucceededFuture(client)
            }
        }
    }
    
    /// Send a message and wait for a responses.
    public func send(
        _ message: SMTPClientMessage
    ) -> EventLoopFuture<[SMTPServerMessage]> {
        return context.sendMessage {
            return self.channel.writeAndFlush(message)
        }
    }
    
    /// Send a message without waiting for a response. This is useful for sending the `QUIT` command.
    public func sendWithoutResponse(
        _ message: SMTPClientMessage
    ) -> EventLoopFuture<Void> {
        return self.channel.writeAndFlush(message)
    }
    
    internal func doHandshake() -> EventLoopFuture<SMTPHandshake> {
        return send(.ehlo(hostname: hostname)).flatMap { messages in
            if let handshake = SMTPHandshake(messages) {
                return self.eventLoop.makeSucceededFuture(handshake)
            }
            
            return self.send(.helo(hostname: self.hostname)).flatMapThrowing { messages in
                guard let handshake = SMTPHandshake(messages) else {
                    throw SMTPError.missingHandshake
                }
                
                return handshake
            }
        }
    }
    
    internal func starttls(configuration: SMTPSSLConfiguration) -> EventLoopFuture<Void> {
        send(.starttls).flatMap { messages in
            guard messages.first?.responseCode == .serviceReady else {
                return self.eventLoop.makeFailedFuture(SMTPError.startTlsFailure)
            }
            
            do {
                let sslContext = try NIOSSLContext(configuration: configuration.makeTlsConfiguration())
                let sslHandler = try NIOSSLClientHandler(context: sslContext, serverHostname: self.hostname)
                
                return self.channel.pipeline.addHandler(sslHandler, position: .first)
            } catch {
                return self.eventLoop.makeFailedFuture(error)
            }
        }
    }
    
    /// Authenticate using the `LOGIN` mechanism. This is the default mechanism used by most SMTP servers.
    public func login(user: String, password: String) -> EventLoopFuture<Void> {
        return send(.authenticateLogin).flatMap { messages -> EventLoopFuture<[SMTPServerMessage]> in
            guard messages.first?.responseCode == .containingChallenge else {
                return self.eventLoop.makeFailedFuture(SMTPError.loginFailure)
            }
            
            return self.send(.authenticateUser(user))
        }.flatMap { messages -> EventLoopFuture<[SMTPServerMessage]> in
            guard messages.first?.responseCode == .containingChallenge else {
                return self.eventLoop.makeFailedFuture(SMTPError.loginFailure)
            }
            
            return self.send(.authenticatePassword(password))
        }.flatMapThrowing { messages in
            guard messages.first?.responseCode == .authSucceeded else {
                throw SMTPError.loginFailure
            }
        }
    }
    
    /// Send a mail.
    public func sendMail(_ mail: Mail) -> EventLoopFuture<Void> {
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
        
        return self.send(.startMail(mail)).status(.commandOK).flatMap {
            let recipientsSent = recipients.map { address in
                return self.send(.mailRecipient(address.email)).status(.commandOK, .willForward)
            }
            
            return EventLoopFuture.andAllSucceed(recipientsSent, on: self.eventLoop)
        }.flatMap {
            self.send(.startMailData).status(.startMailInput)
        }.flatMap {
            self.send(.mailData(mail)).status(.commandOK)
        }
    }
    
    /// Send a mail. This method will wait for the mail to be sent before returning.
    @available(macOS 15, iOS 13, *)
    public func sendMail(_ mail: Mail) async throws {
        try await sendMail(mail).get()
    }
}

extension EventLoopFuture where Value == [SMTPServerMessage] {
    func status(_ status: SMTPResponseCode...) -> EventLoopFuture<Void> {
        flatMapThrowing { messages in
            guard let currentStatus = messages.first?.responseCode else {
                throw SMTPError.sendMailFailed(nil)
            }
            
            for neededStatus in status {
                if currentStatus == neededStatus {
                    return
                }
            }
            
            throw SMTPError.sendMailFailed(currentStatus)
        }
    }
}
