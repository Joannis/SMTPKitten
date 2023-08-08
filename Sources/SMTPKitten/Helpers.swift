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
