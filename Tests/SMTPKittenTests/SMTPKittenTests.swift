import XCTest
import SMTPKitten

final class SMTPKittenTests: XCTestCase {
    func testBasics() async throws {
        try await SMTPClient.withConnection(
            to: "localhost",
            port: 1025,
            ssl: .insecure
        ) { client in
            try await client.sendMail(
                Mail(
                    from: MailUser(name: "Joannis", email: "joannis@unbeatable.software"),
                    to: [MailUser(name: "MailHog User", email: "test@mail.hog")],
                    subject: "Test mail",
                    content: .plain("Hello world")
                )
            )
        }
    }
}
