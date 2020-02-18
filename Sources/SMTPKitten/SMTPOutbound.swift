import Foundation
import NIO

struct AnyError: Error {}

final class SMTPClientOutboundHandler: MessageToByteEncoder {
    public typealias OutboundIn = SMTPClientMessage
    
    init() {}
    
    public func encode(data: SMTPClientMessage, out: inout ByteBuffer) throws {
        switch data {
        case .helo(let hostname):
            out.writeStaticString("HELO ")
            out.writeString(hostname)
        case .ehlo(let hostname):
            out.writeStaticString("EHLO ")
            out.writeString(hostname)
        case .custom(let request):
            out.writeString(request.text)
        case .startMail(let mail):
            out.writeStaticString("MAIL FROM: <")
            out.writeString(mail.from.email)
            out.writeString("> BODY=8BITMIME")
        case .mailRecipient(let address):
            out.writeString("RCPT TO: <\(address)>")
        case .startMailData:
            out.writeStaticString("DATA")
        case .mailData(let mail):
            var headersText = ""
            for header in mail.headers {
                headersText += "\(header.key): \(header.value)\r\n"
            }
            headersText += "Content-Type: text/plain; charset=\"utf-8\"\r\n"
            headersText += "Content-Transfer-Encoding: 7bit\r\n"
            out.writeString(headersText)
            out.writeString("\r\n\(mail.text)\r\n.")
        case .starttls:
            out.writeStaticString("STARTTLS")
        case .authenticatePlain:
            out.writeStaticString("AUTH PLAIN")
        case .authenticateLogin:
            out.writeStaticString("AUTH LOGIN")
        case .authenticateCramMd5:
            out.writeStaticString("AUTH CRAM-MD5")
        case .authenticateXOAuth2(let credentials):
            out.writeStaticString("AUTH XOAUTH2 ")
            out.writeString(credentials)
        case .authenticateUser(let user):
            out.writeString(user.base64Encoded)
        case .authenticatePassword(let password):
            out.writeString(password.base64Encoded)
        case .quit:
            out.writeStaticString("QUIT")
        }
        
        out.writeInteger(cr)
        out.writeInteger(lf)
    }
}

final class SMTPClientInboundHandler: ByteToMessageDecoder {
    public typealias InboundOut = Never
    let context: SMTPClientContext
    
    init(context: SMTPClientContext) {
        self.context = context
    }
    
    public func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        var messages = [SMTPServerMessage]()
        
        while buffer.readableBytes > 0 {
            guard let responseCode = try getResponseCode(buffer: &buffer) else {
                throw SMTPError.incompleteMessage
            }
            
            guard let message = try getResponseMessage(buffer: &buffer) else {
                throw SMTPError.incompleteMessage
            }
            
            messages.append(SMTPServerMessage(code: responseCode, message: message))
        }

        self.context.promise?.succeed(messages)
        return .continue
    }
    
    func getResponseCode(buffer: inout ByteBuffer) throws -> Int? {
        guard let code = buffer.readString(length: 3) else {
            throw SMTPError.invalidCode(nil)
        }
        
        guard let responseCode = Int(code) else {
            throw SMTPError.invalidCode(code)
        }
        
        return responseCode
    }
    
    func getResponseMessage(buffer: inout ByteBuffer) throws -> String? {
        guard
            buffer.readableBytes >= 2,
            let bytes = buffer.getBytes(
                at: buffer.readerIndex,
                length: buffer.readableBytes
            )
        else {
            return nil
        }
        
        for i in 0..<bytes.count - 1 {
            if bytes[i] == cr && bytes[i + 1] == lf {
                guard
                    let messageBytes = buffer.readBytes(length: i),
                    var message = String(bytes: messageBytes, encoding: .utf8)
                else {
                    throw SMTPError.invalidMessage
                }
                
                buffer.moveReaderIndex(forwardBy: 2)
                
                if message.first == " " || message.first == "-" {
                    message.removeFirst()
                }
                
                return message
            }
        }
        
        return nil
    }
    
    public func decodeLast(context: ChannelHandlerContext, buffer: inout ByteBuffer, seenEOF: Bool) throws -> DecodingState {
        return try decode(context: context, buffer: &buffer)
    }
}
