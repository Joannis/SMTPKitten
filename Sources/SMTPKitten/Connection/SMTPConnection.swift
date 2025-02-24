import NIOCore
import NIOPosix
import NIOExtras
import NIOSSL

public actor SMTPConnection {
    public struct Handle: ~Copyable, Sendable {
        enum State {
            case preparing(AsyncStream<SMTPRequest>.Continuation)
            case prepared(AsyncStream<SMTPRequest>.Continuation, handshake: SMTPHandshake)

            var requestWriter: AsyncStream<SMTPRequest>.Continuation {
                switch self {
                case .preparing(let continuation):
                    return continuation
                case .prepared(let continuation, _):
                    return continuation
                }
            }
        }

        let host: String
        var state: State

        var handshake: SMTPHandshake {
            guard case let .prepared(_, handshake) = state else {
                preconditionFailure("SMTPConnection didn't set the SMTPHandshake after getting it")
            }

            return handshake
        }

        internal func send(_ request: ByteBuffer) async throws -> SMTPReply {
            try await withCheckedThrowingContinuation { continuation in
                let request = SMTPRequest(buffer: request, continuation: continuation)
                state.requestWriter.yield(request)
            }
        }
    }

    internal let channel: NIOAsyncChannel<SMTPReplyLine, ByteBuffer>
    fileprivate let requests: AsyncStream<SMTPRequest>
    fileprivate let requestWriter: AsyncStream<SMTPRequest>.Continuation
    fileprivate var error: Error?
    internal var isOpen = false

    fileprivate init(channel: NIOAsyncChannel<SMTPReplyLine, ByteBuffer>) {
        self.channel = channel
        (requests, requestWriter) = AsyncStream.makeStream(of: SMTPRequest.self, bufferingPolicy: .unbounded)
    }

    private func run() async throws -> Never {
        try await withTaskCancellationHandler {
            do {
                defer { isOpen = false }
                try await channel.executeThenClose { inbound, outbound in
                    self.isOpen = true
                    var inboundIterator = inbound.makeAsyncIterator()

                    for await request in requests {
                        do {
                            if request.buffer.readableBytes > 0 {
                                // The first "message" on a connection send by us is empty
                                // Because we're expecting to read data here, not write
                                try await outbound.write(request.buffer)
                            }

                            guard var lastLine = try await inboundIterator.next() else {
                                throw SMTPConnectionError.endOfStream
                            }

                            let code = lastLine.code
                            var lines = [lastLine]

                            while !lastLine.isLast, let nextLine = try await inboundIterator.next() {
                                guard nextLine.code == code else {
                                    throw SMTPConnectionError.protocolError
                                }

                                lines.append(nextLine)
                                lastLine = nextLine
                            }

                            request.continuation.resume(
                                returning: SMTPReply(
                                    code: code,
                                    lines: lines.map(\.contents)
                                )
                            )
                        } catch {
                            request.continuation.resume(throwing: error)
                            throw error
                        }
                    }
                }

                for await request in requests {
                    request.continuation.resume(throwing: SMTPConnectionError.endOfStream)
                }

                throw CancellationError()
            } catch {
                self.error = error
                for await request in requests {
                    request.continuation.resume(throwing: error)
                }
                throw error
            }
        } onCancel: {
            requestWriter.finish()
        }
    }

    public static func withConnection<T>(
        to host: String,
        port: Int = 587,
        ssl: SMTPSSLMode,
        perform: @escaping (inout SMTPConnection.Handle) async throws -> T
    ) async throws -> T {
        let asyncChannel: NIOAsyncChannel<SMTPReplyLine, ByteBuffer> = try await ClientBootstrap(
            group: MultiThreadedEventLoopGroup.singleton
        ).connect(host: host, port: port) { channel in
            do {
                if case .tls(let tls) = ssl.mode {
                    let context = try NIOSSLContext(
                        configuration: tls.configuration.makeTlsConfiguration()
                    )

                    try channel.pipeline.syncOperations.addHandler(
                        NIOSSLClientHandler(context: context, serverHostname: host)
                    )
                }

                try channel.pipeline.syncOperations.addHandlers(
                    ByteToMessageHandler(LineBasedFrameDecoder()),
                    ByteToMessageHandler(SMTPReplyDecoder())
                )

                let asyncChannel = try NIOAsyncChannel<SMTPReplyLine, ByteBuffer>(
                    wrappingChannelSynchronously: channel
                )
                return channel.eventLoop.makeSucceededFuture(asyncChannel)
            } catch {
                return channel.eventLoop.makeFailedFuture(error)
            }
        }

        let connection = SMTPConnection(channel: asyncChannel)
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                var handle = Handle(
                    host: host,
                    state: .preparing(connection.requestWriter)
                )
                // An empty buffer is sent, which the networking layer doesn't (need to) write
                // This happens because the first message is always sent by the server
                // directly after accepting a client
                let serverHello = try await handle.send(ByteBuffer())

                guard serverHello.isSuccessful else {
                    throw SMTPConnectionError.commandFailed(code: serverHello.code)
                }

                // After being accepted as a client, SMTP is request-response based
                var handshake = try await handle.handshake(hostname: host)

                if case .startTLS(let tls) = ssl.mode, handshake.capabilities.contains(.startTLS) {
                    try await handle.starttls(
                        configuration: tls,
                        hostname: host,
                        channel: connection.channel.channel
                    )
                    handshake = try await handle.handshake(hostname: host)
                }

                handle.state = .prepared(connection.requestWriter, handshake: handshake)
                return try await perform(&handle)
            }

            group.addTask {
                try await connection.run()
            }
            guard let result = try await group.next() else {
                throw CancellationError()
            }
            group.cancelAll()
            return result
        }
    }
}

extension SMTPConnection.Handle {
    fileprivate func starttls(
        configuration: SMTPSSLConfiguration,
        hostname: String,
        channel: Channel
    ) async throws {
        try await send(.starttls)
            .status(.serviceReady, or: SMTPConnectionError.startTLSFailure)

        let sslContext = try NIOSSLContext(configuration: configuration.configuration.makeTlsConfiguration())
        let sslHandler = try NIOSSLClientHandler(context: sslContext, serverHostname: hostname)

        try await channel.pipeline.addHandler(sslHandler, position: .first).get()
    }
}
