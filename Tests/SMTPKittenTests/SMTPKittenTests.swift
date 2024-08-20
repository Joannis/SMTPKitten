import NIO
import NIOFoundationCompat
import NIOPosix
import NIOSSL
import XCTest

@testable import SMTPKitten

@available(macOS 13.0, *)
final class SMTPKittenTests: XCTestCase {

    private let defaultSMTPPort = 587

    func testExample() async throws {

        let environment = ProcessInfo.processInfo.environment

        guard
            let hostname = environment["SMTP_HOSTNAME"],
            let username = environment["SMTP_USER"],
            let password = environment["SMTP_PASSWORD"],
            let port = environment["SMTP_PORT"],
            let imagePath = environment["TEST_IMAGE_PATH"],
            let attachmentPath = environment["TEST_ATTACHMENT_PATH"]
        else {
            return XCTFail("Missing environment variables")
        }

        let image = try TestHelpers.fixtureData(for: imagePath)
        let attachment = try TestHelpers.fixtureData(for: attachmentPath)

        let mail = Mail(
            from: MailUser(name: "SMTPKitten Tester", email: username),
            to: ["joannis@unbeatable.software"],
            subject: "Welcome to our app!"
        ) {
            "Welcome to our app, you're all set up & stuff."
            Mail.Image.png(image, filename: "Screenshot.png")
            Mail.Content.alternative("**End** of mail btw.", html: "<b>End</b> of mail btw.")
            Mail.Attachment(attachment, mimeType: "application/png")
        }

        var tlsConfig = TLSConfiguration.clientDefault
        tlsConfig.certificateVerification = .none
        let client = try await SMTPClient.connect(
            hostname: hostname,
            port: Int(port) ?? defaultSMTPPort,
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
            let hostname = environment["SMTP_HOSTNAME"],
            let username = environment["SMTP_USER"],
            let password = environment["SMTP_PASSWORD"],
            let port = environment["SMTP_PORT"],
            let imagePath = environment["TEST_IMAGE_PATH"],
            let attachmentPath = environment["TEST_ATTACHMENT_PATH"]
        else {
            return XCTFail("Missing environment variables")
        }

        let image = try TestHelpers.fixtureData(for: imagePath)
        let attachment = try TestHelpers.fixtureData(for: attachmentPath)

        let contents: [MailContentConvertible] = [
            "Welcome to our app, you're all set up & stuff.",
            Mail.Image.png(image, filename: "Screenshot.png"),
            Mail.Content.alternative("**End** of mail btw.", html: "<b>End</b> of mail btw."),
            Mail.Attachment(attachment, mimeType: "application/png"),
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
            port: Int(port) ?? defaultSMTPPort,
            ssl: .startTLS(configuration: .default)
        )

        try await client.login(
            user: username,
            password: password
        )

        try await client.sendMail(mail)
    }
}
