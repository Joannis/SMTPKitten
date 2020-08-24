import NIO
import NIOSSL

public enum SMTPSSLConfiguration {
    case `default`
    case customRoot(path: String)
    
    internal func makeTlsConfiguration() -> TLSConfiguration {
        switch self {
        case .default:
            return TLSConfiguration.forClient()
        case .customRoot(let path):
            return TLSConfiguration.forClient(
                certificateVerification: .fullVerification,
                trustRoots: .file(path)
            )
        }
    }
}

public enum SMTPSSLMode {
    case startTLS(configuration: SMTPSSLConfiguration)
    case tls(configuration: SMTPSSLConfiguration)
    case insecure
}

internal final class SMTPClientContext {
    private(set) var promise: EventLoopPromise<[SMTPServerMessage]>!
    private var lastResponseFuture: EventLoopFuture<Void>!
    let eventLoop: EventLoop
    
    init(eventLoop: EventLoop) {
        self.eventLoop = eventLoop
        
        // Has initial future because the first response is without request
        // That response is ignored
        let promise = eventLoop.makePromise(of: [SMTPServerMessage].self)
        self.promise = promise
        self.lastResponseFuture = promise.futureResult.map { _ in
            self.promise = nil
        }
    }
    
    func sendMessage(sendMessage: @escaping () -> EventLoopFuture<Void>) -> EventLoopFuture<[SMTPServerMessage]> {
        let promise = eventLoop.makePromise(of: [SMTPServerMessage].self)
        
        let response = lastResponseFuture!.flatMap { _ -> EventLoopFuture<[SMTPServerMessage]> in
            self.promise = promise
            return sendMessage()
                .flatMap { promise.futureResult }
                .map { messages in
                    self.promise = nil
                    return messages
                }
        }
        
        self.lastResponseFuture = response.map { _ in }
        
        return response
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
    ) -> EventLoopFuture<SMTPClient> {
        let eventLoop = MultiThreadedEventLoopGroup(numberOfThreads: 1).next()
        let context = SMTPClientContext(eventLoop: eventLoop)
        let parser = ByteToMessageHandler(SMTPClientInboundHandler(context: context))
        let serializer = MessageToByteHandler(SMTPClientOutboundHandler())
        
        return ClientBootstrap(group: eventLoop)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(IPPROTO_TCP), TCP_NODELAY), value: 1)
            .channelInitializer { channel in
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
        }.connect(host: hostname, port: port).map { channel in
            return SMTPClient(
                channel: channel,
                eventLoop: eventLoop,
                context: context,
                hostname: hostname
            )
        }.flatMap { client in
            return client.doHandshake().flatMap { handshake in
                client.handshake = handshake
                
                if case .startTLS(let configuration) = ssl {
                    if !handshake.starttls {
                        return eventLoop.makeFailedFuture(SMTPError.starttlsUnsupportedByServer)
                    }
                    
                    return client.starttls(configuration: configuration).flatMap {
                        return client.doHandshake()
                    }.map { handshake in
                        client.handshake = handshake
                        return client
                    }
                }
                
                return eventLoop.makeSucceededFuture(client)
            }
        }
    }
    
    public func send(
        _ message: SMTPClientMessage
    ) -> EventLoopFuture<[SMTPServerMessage]> {
        return context.sendMessage {
            return self.channel.writeAndFlush(message)
        }
    }
    
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
}

extension EventLoopFuture where Value == [SMTPServerMessage] {
    func status(_ status: SMTPResponseCode...) -> EventLoopFuture<Void> {
        flatMapThrowing { messages in
            guard let currentStatus = messages.first?.responseCode else {
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
}
