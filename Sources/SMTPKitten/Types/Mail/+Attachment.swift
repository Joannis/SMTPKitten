import Foundation
import NIOFoundationCompat
import NIOCore

extension Mail {
    public struct Attachment: Sendable {
        let mime: String
        let base64: String
        let filename: String?
        let contentDisposition: Disposition

        public var content: Content { .single(.attachment(self)) }

        public init(
            _ buffer: Data,
            mimeType mime: String,
            filename: String? = nil,
            contentDisposition: Disposition = .inline
        ) {
            self.mime = mime
            self.base64 = buffer.base64EncodedString(options: .lineLength76Characters)
            self.filename = filename
            self.contentDisposition = contentDisposition
        }

        public init(
            _ buffer: ByteBuffer,
            mimeType mime: String,
            filename: String? = nil,
            contentDisposition: Disposition = .inline
        ) {
            self.init(
                buffer.getData(at: 0, length: buffer.readableBytes)!,
                mimeType: mime,
                filename: filename,
                contentDisposition: contentDisposition
            )
        }
    }
}
