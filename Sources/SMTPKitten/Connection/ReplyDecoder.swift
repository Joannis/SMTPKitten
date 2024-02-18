import NIOCore

enum SMTPReplyDecodingError: Error {
    case invalidReplyFormat
    case invalidReplyCode(String)
}

struct SMTPReplyDecoder: ByteToMessageDecoder {
    typealias InboundOut = SMTPReplyLine

    mutating func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        guard
            buffer.readableBytes >= 3,
            let codeString = buffer.readString(length: 3)
        else {
            throw SMTPReplyDecodingError.invalidReplyFormat
        }

        guard
            let code = Int(codeString),
            code >= 200, code < 600
        else {
            throw SMTPReplyDecodingError.invalidReplyCode(codeString)
        }

        switch buffer.readInteger() as UInt8? {
        case 0x2d: // - (hyphen, minus)
            let line = SMTPReplyLine(code: code, contents: buffer, isLast: false)
            context.fireChannelRead(wrapInboundOut(line))
            return .continue
        case 0x20: // Space
            let line = SMTPReplyLine(code: code, contents: buffer, isLast: true)
            context.fireChannelRead(wrapInboundOut(line))
            return .continue
        default:
            throw SMTPReplyDecodingError.invalidReplyFormat
        }
    }
}
