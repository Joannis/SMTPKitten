import NIO
import NIOExtras
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
    let promise: EventLoopPromise<SMTPServerMessage>
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
    ) -> EventLoopFuture<SMTPServerMessage> {
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
    
    func receive(_ messages: SMTPServerMessage) {
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
    let auth: Set<SMTPAuthMethod>
    
    init?(_ message: SMTPServerMessage) {
        guard message.responseCode == .commandOK else {
            return nil
        }
        
        var starttls = false
        var auth = Set<SMTPAuthMethod>()
        
        for line in message.lines {
            let capability = line.uppercased()
            
            if capability == "STARTTLS" {
                starttls = true
            }
            
            
            if line.contains("AUTH"), auth.isEmpty {
                auth = Set(line.components(separatedBy: " ").compactMap { SMTPAuthMethod(rawValue: $0) })
            }
        }
        
        self.starttls = starttls
        self.auth = auth
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
        ssl: SMTPSSLMode,
        on eventLoop: EventLoop = MultiThreadedEventLoopGroup(numberOfThreads: 1).next()
    ) async throws -> SMTPClient {
        return try await connect(hostname: hostname, port: port, ssl: ssl, eventLoop: eventLoop)
    }
    
    /// Connect to an SMTP server.
    public static func connect(
        hostname: String,
        channel: Channel,
        ssl: SMTPSSLMode,
        on eventLoop: EventLoop = MultiThreadedEventLoopGroup(numberOfThreads: 1).next()
    ) async throws -> SMTPClient {
        let context = SMTPClientContext(eventLoop: channel.eventLoop)
        
        let lineBasedFrameDecoder = ByteToMessageHandler(LineBasedFrameDecoder())
        let parser = SMTPClientInboundHandler(context: context)
        let serializer = MessageToByteHandler(SMTPClientOutboundHandler())
        var handlers: [ChannelHandler] = [lineBasedFrameDecoder, parser, serializer, ErrorCloseHandler()]
        
        switch ssl {
        case .insecure, .startTLS:
            break
        case let .tls(configuration):
            let sslContext = try NIOSSLContext(configuration: configuration.makeTlsConfiguration())
            let sslHandler = try NIOSSLClientHandler(context: sslContext, serverHostname: hostname)
            
            handlers.insert(sslHandler, at: 0)
        }
        
        try await channel.pipeline.addHandlers(handlers)
        let client = SMTPClient(
            channel: channel,
            eventLoop: channel.eventLoop,
            context: context,
            hostname: hostname
        )
        
        do {
            _ = try await client.send(.none)
        }
        
        do {
            var handshake = try await client.doHandshake()
            client.handshake = handshake
            
            if case .startTLS(let configuration) = ssl {
                if !handshake.starttls {
                    throw SMTPError.starttlsUnsupportedByServer
                }
                
                try await client.starttls(configuration: configuration)
                handshake = try await client.doHandshake()
                client.handshake = handshake
            }
        }
        
        return client
    }
        
    /// Connect to an SMTP server.
    public static func connect(
        hostname: String,
        port: Int = 587,
        ssl: SMTPSSLMode,
        eventLoop: EventLoop
    ) async throws -> SMTPClient {
        let context = SMTPClientContext(eventLoop: eventLoop)
        
        let channel = try await ClientBootstrap(group: eventLoop).channelInitializer { channel in
            let lineBasedFrameDecoder = ByteToMessageHandler(LineBasedFrameDecoder())
            let parser = SMTPClientInboundHandler(context: context)
            let serializer = MessageToByteHandler(SMTPClientOutboundHandler())
            var handlers: [ChannelHandler] = [lineBasedFrameDecoder, parser, serializer, ErrorCloseHandler()]
            
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
        }.connect(host: hostname, port: port).get()
        
        let client = SMTPClient(
            channel: channel,
            eventLoop: eventLoop,
            context: context,
            hostname: hostname
        )
        
        do {
            _ = try await client.send(.none)
        }
        
        do {
            var handshake = try await client.doHandshake()
            client.handshake = handshake
            
            if case .startTLS(let configuration) = ssl {
                if !handshake.starttls {
                    throw SMTPError.starttlsUnsupportedByServer
                }
                
                try await client.starttls(configuration: configuration)
                handshake = try await client.doHandshake()
                client.handshake = handshake
            }
        }
                
        return client
    }
    
    /// Send a message and wait for a responses.
    public func send(
        _ message: SMTPClientMessage
    ) async throws -> SMTPServerMessage {
        return try await context.sendMessage {
            return self.channel.writeAndFlush(message)
        }.get()
    }
    
    /// Send a message without waiting for a response. This is useful for sending the `QUIT` command.
    public func sendWithoutResponse(
        _ message: SMTPClientMessage
    ) -> EventLoopFuture<Void> {
        return self.channel.writeAndFlush(message)
    }
    
    internal func doHandshake() async throws -> SMTPHandshake {
        var message = try await send(.ehlo(hostname: hostname))
        if let handshake = SMTPHandshake(message) {
            return handshake
        }
            
        message = try await self.send(.helo(hostname: self.hostname))
        guard let handshake = SMTPHandshake(message) else {
            throw SMTPError.missingHandshake
        }
                
        return handshake
    }
    
    internal func starttls(configuration: SMTPSSLConfiguration) async throws {
        try await send(.starttls)
            .status(.serviceReady, or: SMTPError.startTlsFailure)
        
        let sslContext = try NIOSSLContext(configuration: configuration.makeTlsConfiguration())
        let sslHandler = try NIOSSLClientHandler(context: sslContext, serverHostname: self.hostname)
        
        try await self.channel.pipeline.addHandler(sslHandler, position: .first)
    }
    
    public func login(user: String, password: String, using method: SMTPAuthMethod = .login) async throws {
        try await auth(using: method, user: user, password: password)
    }
    
    private func auth(using method: SMTPAuthMethod, user: String, password: String) async throws {
        switch method {
        case .plain:
            try await send(.authenticatePlain(SMTPPlainCreds(user: user, password: password)))
                .status(.authSucceeded, or: SMTPError.loginFailure)
        case .login:
            try await send(.authenticateLogin)
                .status(.containingChallenge, or: SMTPError.loginFailure)
            
            try await send(.authenticateUser(user))
                .status(.containingChallenge, or: SMTPError.loginFailure)
            
            try await self.send(.authenticatePassword(password))
                .status(.authSucceeded, or: SMTPError.loginFailure)
        case .crammd5:
            assertionFailure("Unsupported for now")
            throw SMTPError.incompatibleAuthMethod(method)
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

extension SMTPServerMessage {
    func status(_ status: SMTPResponseCode..., or error: Error? = nil) throws {
        let error = error ?? SMTPError.sendMailFailed(code)
        
        guard let currentStatus = responseCode else {
            throw error
        }
        
        for neededStatus in status {
            if currentStatus == neededStatus {
                return
            }
        }
        
        throw error
    }
}
