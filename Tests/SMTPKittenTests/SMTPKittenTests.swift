import XCTest
import NIO
import NIOFoundationCompat
import NIOSSL
@testable import SMTPKitten
import NIOPosix

@available(macOS 13.0, *)
final class SMTPKittenTests: XCTestCase {
    func testExample() async throws {
        let environment = ProcessInfo.processInfo.environment

        guard
            let hostname = environment["TEST_HOST"],
            let username = environment["TEST_USERNAME"],
            let password = environment["TEST_PASSWORD"],
            let imagePath = environment["TEST_IMAGE_PATH"],
            let attachmentPath = environment["TEST_ATTACHMENT_PATH"]
        else {
            return XCTFail("Missing environment variables")
        }

        let image = try Data(contentsOf: URL(filePath: imagePath))
        let attachment = try Data(contentsOf: URL(filePath: attachmentPath))

        let mail = Mail(
            from: MailUser(name: "SMTPKitten Tester", email: username),
            to: ["joannis@unbeatable.software"],
            subject: "Welcome to our app!"
        ) {
            "Welcome to our app, you're all set up & stuff."
            Mail.Image.png(image, filename: "Screenshot.png")
            Mail.Content.alternative("**End** of mail btw.", html: "<b>End</b> of mail btw.")
            Mail.Attachment(attachment, mimeType: "application/pdf")
        }
        
        var tlsConfig = TLSConfiguration.clientDefault
        tlsConfig.certificateVerification = .none
        let client = try await SMTPClient.connect(
            hostname: hostname,
            port: 587,
            ssl: .startTLS(configuration: .default)
        )
        
        try await client.login(
            user: username,
            password: password
        )
        
        try await client.sendMail(mail)
    }
    
    func testMutableContentExample() async throws {
        
        let environment = ProcessInfo.processInfo.environment

        guard
            let hostname = environment["TEST_HOST"],
            let username = environment["TEST_USERNAME"],
            let password = environment["TEST_PASSWORD"],
            let imagePath = environment["TEST_IMAGE_PATH"],
            let attachmentPath = environment["TEST_ATTACHMENT_PATH"]
        else {
            return XCTFail("Missing environment variables")
        }

        let image = try Data(contentsOf: URL(filePath: imagePath))
        let attachment = try Data(contentsOf: URL(filePath: attachmentPath))

        var contents: [MailContentConvertible] = [
            "Welcome to our app, you're all set up & stuff."
            Mail.Image.png(image, filename: "Screenshot.png")
            Mail.Content.alternative("**End** of mail btw.", html: "<b>End</b> of mail btw.")
            Mail.Attachment(attachment, mimeType: "application/pdf")
        ]
        
        let mail = Mail(
            from: MailUser(name: "SMTPKitten Tester", email: username),
            to: ["joannis@unbeatable.software"],
            subject: "Welcome to our app!"
        ) {
            contents
        }
        
        var tlsConfig = TLSConfiguration.clientDefault
        tlsConfig.certificateVerification = .none
        let client = try await SMTPClient.connect(
            hostname: hostname,
            port: 587,
            ssl: .startTLS(configuration: .default)
        )
        
        try await client.login(
            user: username,
            password: password
        )
        
        try await client.sendMail(mail)
    }
    
    static var allTests = [
        ("testExample", testExample),
        ("testMutableContentExample", testMutableContentExample),
    ]
}
