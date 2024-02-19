import NIO
import Foundation

let cr: UInt8 = 0x0d
let lf: UInt8 = 0x0a
fileprivate let smtpDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "EEE, d MMM yyyy HH:mm:ss ZZZ"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter
}()

extension String {
    var base64Encoded: String {
        Data(utf8).base64EncodedString()
    }
}

extension Date {
    var smtpFormatted: String {
        return smtpDateFormatter.string(from: self)
    }
}

extension SMTPReply {
    func status(_ status: SMTPCode..., or error: Error? = nil) throws {
        let error = error ?? SMTPClientError.commandFailed(code: code)

        guard let currentStatus = SMTPCode(rawValue: code) else {
            throw error
        }

        for neededStatus in status {
            if currentStatus == neededStatus {
                return
            }
        }

        throw error
    }

    func isSuccessful(or error: Error? = nil) throws {
        guard self.isSuccessful else {
            throw error ?? SMTPClientError.commandFailed(code: code)
        }
    }
}
