import NIOCore
import Foundation

extension Mail.Content.Block {
    var headers: [String: String] {
        switch self {
        case .plain:
            return [
                "Content-Type": "text/plain; charset=utf-8",
            ]
        case .html:
            return [
                "Content-Type": "text/html; charset=utf-8",
            ]
        case .alternative(let boundary, _, _):
            return [
                "Content-Type": "multipart/alternative; boundary=\(boundary)",
            ]
        case .image(let image):
            var disposition = image.contentDisposition.disposition.rawValue

            if let filename = image.filename {
                disposition += "; filename=\"\(filename)\""
            }

            return [
                "Content-Type": image.mime,
                "Content-Disposition": disposition,
                "Content-ID": image.contentId.id,
                "Content-Transfer-Encoding": "base64",
            ]
        case .attachment(let attachment):
            var disposition = attachment.contentDisposition.disposition.rawValue

            if let filename = attachment.filename {
                disposition += "; filename=\"\(filename)\""
            }

            return [
                "Content-Type": attachment.mime,
                "Content-Disposition": disposition,
                "Content-Transfer-Encoding": "base64",
            ]
        }
    }

    @discardableResult
    internal func writePayload(into buffer: inout ByteBuffer) -> Int {
        switch self {
        case .plain(let text):
            return buffer.writeString(text)
        case .html(let html):
            return buffer.writeString(html)
        case .alternative(let boundary, let text, let html):
            return buffer.writeString("""
            --\(boundary)
            Content-Type: text/plain; charset=utf-8\r
            Content-Transfer-Encoding: 8BIT\r

            \(text)
            --\(boundary)
            Content-Type: text/html; charset=utf-8
            Content-Transfer-Encoding: 8BIT

            \(html)
            --\(boundary)--
            """)
        case .image(let image):
            return buffer.writeString(image.base64)
        case .attachment(let attachment):
            return buffer.writeString(attachment.base64)
        }
    }
}

extension Mail.Content {
    internal var headers: [String: String] {
        switch _content {
        case .single(let block):
            return block.headers
        case .multipart(boundary: let boundary, blocks: _):
            return [
                "Content-Type": "multipart/mixed; boundary=\(boundary)",
            ]
        }
    }

    @discardableResult
    internal func writePayload(into buffer: inout ByteBuffer) -> Int {
        switch _content {
        case .multipart(boundary: let boundary, blocks: let blocks):
            var written = 0
            for block in blocks {
                let headers = block.headers.map { "\($0): \($1)" }.joined(separator: "\r\n")
                written += buffer.writeString("""
                --\(boundary)
                \(headers)


                """)

                written += block.writePayload(into: &buffer)
                written += buffer.writeString("\n")
            }

            return written
        case .single(let block):
            return block.writePayload(into: &buffer)
        }
    }
}

extension Mail {
    // TODO: Attachments

    /// Generates the headers of the mail.
    internal var headers: [String: String] {
        var headers = customHeaders
        headers.reserveCapacity(16)

        headers["MIME-Version"] = "1.0"
        headers["Message-Id"] = "<\(UUID().uuidString)@localhost>"
        headers["Date"] = Date().smtpFormatted
        headers["From"] = from.smtpFormatted
        headers["To"] = to.map(\.smtpFormatted)
            .joined(separator: ", ")

        if let replyTo {
            headers["Reply-To"] = replyTo.smtpFormatted
        }

        if !cc.isEmpty {
            headers["Cc"] = cc.map { $0.smtpFormatted }
                .joined(separator: ", ")
        }

        if let data = subject.data(using: .utf8) {
            headers["Subject"] = "=?utf-8?B?\(data.base64EncodedString())?="
        } else {
            headers["Subject"] = subject
        }

        return headers
    }
}
