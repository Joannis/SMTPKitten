import XCTest
import NIOSSL
@testable import SMTPKitten
import NIOPosix

final class SMTPKittenTests: XCTestCase {
    func testExample() throws {
        let mail = Mail(
            from: MailUser(name: "info@example.com", email: "info@example.com"),
            to: [MailUser(name: "info@example.com", email: "info@example.com")],
            subject: "Welcome to our app!",
            contentType: .plain,
            text: "Welcome to our app, you're all set up & stuff."
        )
        
        var tlsConfig = TLSConfiguration.clientDefault
        tlsConfig.certificateVerification = .none
        let client = try SMTPClient.connect(
            hostname: "localhost",
            port: 587,
            ssl: .startTLS(configuration: .custom(tlsConfig))
        ).wait()
        
        try client.login(
            user: "info@example.com",
            password: "passwd1"
        ).wait()
        
        try client.sendMail(mail).wait()
    }
    
    static var allTests = [
        ("testExample", testExample),
    ]
}
