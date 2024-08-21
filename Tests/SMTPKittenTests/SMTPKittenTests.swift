import XCTest
import SMTPKitten

final class SMTPKittenTests: XCTestCase {
    var port: Int {
        ProcessInfo.processInfo.environment["SMTP_PORT"].flatMap(Int.init) ?? 1025
    }

    var hostname: String {
        ProcessInfo.processInfo.environment["SMTP_HOSTNAME"] ?? "localhost"
    }

    func testBasics() async throws {
        try await SMTPClient.withConnection(
            to: hostname,
            port: port,
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

    func testAlternative() async throws {
        let html = "<p>Hello, from Swift!</p>"

        try await SMTPClient.withConnection(
            to: hostname,
            port: port,
            ssl: .insecure
        ) { client in
            let mail = Mail(
                from: MailUser(name: "My Mailer", email: "noreply@example.com"),
                to: [MailUser(name: "John Doe", email: "john.doe@example.com")],
                subject: "Welcome to our app!",
                content: .alternative("Welcome to our app, you're all set up & stuff.", html: html)
            )

            try await client.sendMail(mail)
        }
    }
}
