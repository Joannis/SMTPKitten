import NIOCore
import NIOPosix
import NIOExtras
import NIOSSL

public actor SMTPClient {
    let channel: NIOAsyncChannel<SMTPReplyLine, ByteBuffer>
    fileprivate let requests: AsyncStream<SMTPRequest>
    fileprivate let requestWriter: AsyncStream<SMTPRequest>.Continuation
    fileprivate var error: Error?

    init(channel: NIOAsyncChannel<SMTPReplyLine, ByteBuffer>) {
        self.channel = channel
        (requests, requestWriter) = AsyncStream.makeStream(of: SMTPRequest.self, bufferingPolicy: .unbounded)
    }

    internal func send(_ request: ByteBuffer) async throws -> SMTPReply {
        try await withCheckedThrowingContinuation { continuation in
            let request = SMTPRequest(buffer: request, continuation: continuation)
            requestWriter.yield(request)
        }
    }

    internal func run() async throws {
        do {
            try await channel.executeThenClose { inbound, outbound in
                var inboundIterator = inbound.makeAsyncIterator()

                for await request in requests {
                    if request.buffer.readableBytes > 0 {
                        // The first "message" on a connection send by us is empty
                        // Because we're expecting to read data here, not write
                        try await outbound.write(request.buffer)
                    }

                    guard var lastLine = try await inboundIterator.next() else {
                        throw SMTPClientError.endOfStream
                    }

                    let code = lastLine.code
                    var lines = [lastLine]

                    while !lastLine.isLast, let nextLine = try await inboundIterator.next() {
                        guard nextLine.code == code else {
                            throw SMTPClientError.protocolError
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
                }
            }

            requestWriter.finish()
            for await request in requests {
                request.continuation.resume(throwing: SMTPClientError.endOfStream)
            }
        } catch {
            self.error = error
            requestWriter.finish()
            for await request in requests {
                request.continuation.resume(throwing: error)
            }
            throw error
        }
    }

    nonisolated fileprivate func starttls(
        configuration: SMTPSSLConfiguration,
        hostname: String
    ) async throws {
        try await send(.starttls)
            .status(.serviceReady, or: SMTPClientError.startTLSFailure)

        let sslContext = try NIOSSLContext(configuration: configuration.configuration.makeTlsConfiguration())
        let sslHandler = try NIOSSLClientHandler(context: sslContext, serverHostname: hostname)

        try await self.channel.channel.pipeline.addHandler(sslHandler, position: .first)
    }

    public static func withConnection<T>(
        to host: String,
        port: Int = 587,
        ssl: SMTPSSLMode,
        perform: (SMTPClient) async throws -> T
    ) async throws -> T {
        let asyncChannel: NIOAsyncChannel<SMTPReplyLine, ByteBuffer> = try await ClientBootstrap(
            group: NIOSingletons.posixEventLoopGroup
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
                    ByteToMessageHandler(LineBasedFrameDecoder())
                )

                let asyncChannel = try NIOAsyncChannel<SMTPReplyLine, ByteBuffer>(
                    wrappingChannelSynchronously: channel,
                    configuration: .init()
                )
                return channel.eventLoop.makeSucceededFuture(asyncChannel)
            } catch {
                return channel.eventLoop.makeFailedFuture(error)
            }
        }

        let client = SMTPClient(channel: asyncChannel)
        return try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await client.run()
            }

            let handshake = try await client.handshake(hostname: host)
            if case .startTLS(let tls) = ssl.mode, handshake.starttls {
                try await client.starttls(configuration: tls, hostname: host)
            }
            return try await perform(client)
        }
    }
}
