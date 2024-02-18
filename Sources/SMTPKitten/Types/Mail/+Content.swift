import Foundation
import NIO

extension Mail {
    public struct Content: Sendable {
        public struct ID: Hashable, Sendable {
            let id: String

            public init(named name: String = UUID().uuidString) {
                self.id = name
            }
        }

        internal enum Block: Sendable {
            case plain(String)
            case html(String)
            case image(Image)
            case attachment(Attachment)
            case alternative(boundary: String, text: String, html: String)
        }

        internal enum _Content: Sendable {
            case single(Block)
            case multipart(boundary: String, blocks: [Block])
        }

        internal let _content: _Content
        public var content: Content { self }

        internal var blocks: [Block] {
            switch _content {
            case .single(let block):
                return [block]
            case .multipart(_, let blocks):
                return blocks
            }
        }

        internal static func single(_ block: Block) -> Content {
            return Content(_content: .single(block))
        }

        internal static func multipart(
            _ blocks: [Block],
            boundary: String = UUID().uuidString
        ) -> Content {
            return Content(_content: .multipart(boundary: boundary, blocks: blocks))
        }

        public static func multipart(
            _ content: [Content],
            boundary: String = UUID().uuidString
        ) -> Content {
            let blocks = content.flatMap(\.blocks)
            return Content(_content: .multipart(boundary: boundary, blocks: blocks))
        }

        public static func plain(_ text: String) -> Content {
            return .single(.plain(text))
        }

        public static func html(_ html: String) -> Content {
            return .single(.html(html))
        }

        public static func alternative(_ text: String, html: String) -> Content {
            return .single(.alternative(boundary: UUID().uuidString, text: text, html: html))
        }

        public static func alternative(_ blocks: [Content]) -> Content {
            return .multipart(blocks.flatMap(\.blocks))
        }
    }
}

extension Mail.Content {
    public struct Image: Sendable {
        let mime: String
        let base64: String
        let filename: String?
        let contentDisposition: Mail.Disposition
        let contentId: ID

        public var content: Mail.Content { .single(.image(self)) }

        public static func png(
            _ buffer: Data,
            filename: String? = nil,
            contentDisposition: Mail.Disposition = .inline,
            contentId: ID = .init()
        ) -> Image {
            return Image(
                mime: "image/png",
                base64: buffer.base64EncodedString(options: .lineLength76Characters),
                filename: filename,
                contentDisposition: contentDisposition,
                contentId: contentId
            )
        }

        public static func jpeg(
            _ buffer: Data,
            filename: String? = nil,
            contentDisposition: Mail.Disposition = .inline,
            contentId: ID = .init()
        ) -> Image {
            return Image(
                mime: "image/jpeg",
                base64: buffer.base64EncodedString(options: .lineLength76Characters),
                filename: filename,
                contentDisposition: contentDisposition,
                contentId: contentId
            )
        }
    }
}
