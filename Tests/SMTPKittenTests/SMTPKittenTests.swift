import XCTest
import NIOSSL
@testable import SMTPKitten
import NIOPosix

final class SMTPKittenTests: XCTestCase {
    func testExample() async throws {
        let mail = Mail(
            from: "joannis@orlandos.nl",
            to: ["joannis@unbeatable.software"],
            subject: "Welcome to our app!",
            contentType: .plain,
            text: "Welcome to our app, you're all set up & stuff."
        )
        
        var tlsConfig = TLSConfiguration.clientDefault
        tlsConfig.certificateVerification = .none
        let client = try await SMTPClient.connect(
            hostname: "smtp.example.com",
            port: 587,
            ssl: .startTLS(configuration: .default)
        )
        
        try await client.login(
            user: "info@example.com",
            password: "passwd1"
        )
        
        try await client.sendMail(mail)
    }
    
    static var allTests = [
        ("testExample", testExample),
    ]
}
