import ServiceLifecycle

enum SMTPClientError: Error {
    case notRunning
}

public actor SMTPClient: Service {
    typealias SendMails = AsyncStream<(Mail, CheckedContinuation<Void, Error>)>

    let host: String
    let port: Int
    let ssl: SMTPSSLMode
    let onCreateConnection: (inout SMTPConnection.Handle) async throws -> Void
    var writeMail: SendMails.Continuation?

    // How long to wait before retrying to connect to the server
    private nonisolated let backoff = Duration.seconds(5)

    init(
        to host: String,
        port: Int = 587,
        ssl: SMTPSSLMode,
        onCreateConnection: @escaping (inout SMTPConnection.Handle) async throws -> Void
    ) {
        self.host = host
        self.port = port
        self.ssl = ssl
        self.onCreateConnection = onCreateConnection
    }
    
    public func sendMail(_ mail: Mail) async throws {
        guard let writeMail else {
            throw SMTPClientError.notRunning
        }

        try await withCheckedThrowingContinuation { continuation in
            writeMail.yield((mail, continuation))
        }
    }

    public func run() async throws {
        precondition(writeMail == nil, "Cannot run SMTPClient twice in parallel")

        let queries = SendMails.makeStream()
        var iterator = queries.stream.makeAsyncIterator()
        self.writeMail = queries.continuation
        await withTaskCancellationHandler {
            while !Task.isCancelled {
                do {
                    try await SMTPConnection.withConnection(
                        to: self.host,
                        port: self.port,
                        ssl: self.ssl
                    ) { handle in
                        try await self.onCreateConnection(&handle)
                        while let (mail, continuation) = await iterator.next() {
                            do {
                                try await handle.sendMail(mail)
                                continuation.resume()
                            } catch {
                                continuation.resume(throwing: error)
                            }
                        }
                    }

                    try await Task.sleep(for: backoff)
                } catch {}
            }
            self.writeMail = nil
        } onCancel: {
            queries.continuation.finish()
        }

        while let (_, continuation) = await iterator.next() {
            continuation.resume(throwing: CancellationError())
        }
    }
}
