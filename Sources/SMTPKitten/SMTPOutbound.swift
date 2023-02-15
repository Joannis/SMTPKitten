import Foundation
import NIO

struct AnyError: Error {}

final class SMTPClientOutboundHandler: MessageToByteEncoder {
    public typealias OutboundIn = SMTPClientMessage
    
    init() {}
    
    public func encode(data: SMTPClientMessage, out: inout ByteBuffer) throws {
        switch data {
        case .none:
            return
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

final class SMTPClientInboundHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = Never
    
    let context: SMTPClientContext
    var responseCode: Int?
    var lines = [String]()
    
    init(context: SMTPClientContext) {
        self.context = context
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        
        do {
            let responseCode = try getResponseCode(buffer: &buffer)
            self.responseCode = responseCode
            
            if let lines = try getResponseMessage(buffer: &buffer) {
                self.context.receive(SMTPServerMessage(code: responseCode, lines: lines))
            }
        } catch {
            self.context.disconnect()
            context.fireErrorCaught(SMTPError.incompleteMessage)
            context.close(promise: nil)
        }
    }
    
    func getResponseCode(buffer: inout ByteBuffer) throws -> Int {
        guard let code = buffer.readString(length: 3) else {
            throw SMTPError.invalidCode(nil)
        }
        
        guard let responseCode = Int(code) else {
            throw SMTPError.invalidCode(code)
        }
        
        if let knownResponseCode = self.responseCode, knownResponseCode != responseCode {
            throw SMTPError.invalidMessage
        }
        
        return responseCode
    }
    
    func getResponseMessage(buffer: inout ByteBuffer) throws -> [String]? {
        guard
            var line = buffer.readString(length: buffer.readableBytes)
        else {
            throw SMTPError.invalidMessage
        }
        
        let marker = line.removeFirst()
        lines.append(line)
        
        if marker == " " {
            defer {
                // Reset to next message
                lines.removeAll(keepingCapacity: true)
                responseCode = nil
            }
            
            return lines
        } else if marker == "-"  {
            return nil
        } else {
            throw SMTPError.invalidMessage
        }
        
        return nil
    }
}
