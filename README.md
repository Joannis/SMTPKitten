<a href="https://unbeatable.software"><img src="./assets/SMTPKitten.png" /></a>

To get started, add the SMTPKitten dependency:

```swift
.package(url: "https://github.com/joannis/SMTPKitten.git", from: "1.0.0"),
```

And add it as a dependency of your target:

```swift
.product(name: "SMTPKitten", package: "SMTPKitten"),
```

### Create a connection

```swift
try await SMTPConnection.withConnection(
    to: "localhost",
    port: 1025,
    ssl: .insecure
) { client in
    // 1. Authenticate
    try await client.login(
        user: "xxxxxx",
        password: "hunter2"
    )
    
    // 2. Send emails
}
```

### Sending Emails

Before sending an email, first contruct a `Mail` object. Then, call `sendMail` on the client.

```swift
let mail = Mail(
    from: MailUser(name: "My Mailer", email: "noreply@example.com"),
    to: [MailUser(name: "John Doe", email: "john.doe@example.com")],
    subject: "Welcome to our app!",
    content: .plain("Welcome to our app, you're all set up & stuff.")
)

try await client.sendMail(mail)
```

The `Mail.Content` type supports various other types of information including HTML, Alternative (HTML with Plaintext fallback) and multipart.

### Community

[Join our Discord](https://discord.gg/H6799jh) for any questions and friendly banter.

If you need hands-on support on your projects, our team is available at [hello@unbeatable.software](mailto:hello@unbeatable.software).
