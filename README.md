# SMTPKitten

To get started, add the SMTPKitten dependency:

```swift
.package(url: "https://github.com/joannis/SMTPKitten.git", from: "0.2.0"),
```

And add it as a dependency of your target:

```swit
.product(name: "SMTPKitten", package: "SMTPKitten"),
```

### Create a connection

```swift
let client = try await SMTPClient.connect(
    hostname: "smtp.example.com",
    ssl: .startTLS(configuration: .default)
)
try await client.login(
    user: "noreply@example.com",
    password: "pas$w0rd"
)
```

### Sending Emails

Before sending an email, first contruct a `Mail` object. Then, call `sendMail` on the client.

```swift
let mail = Mail(
    from: MailUser(name: "My Mailer", email: "noreply@example.com"),
    to: [MailUser(name: "John Doe", email: "john.doe@example.com")],
    subject: "Welcome to our app!",
    contentType: .plain,
    text: "Welcome to our app, you're all set up & stuff."
)

try await client.sendMail(mail)
```

You can also use a result builder pattern for creating emails.

```swift
let image = try Data(contentsOf: URL(filePath: imagePath))
let attachment = try Data(contentsOf: URL(filePath: attachmentPath))

let mail = Mail(
    from: MailUser(name: "SMTPKitten Tester", email: "noreply@example.com"),
    to: ["joannis@unbeatable.software"],
    subject: "Welcome to our app!"
) {
    "Welcome to our app, you're all set up & stuff."
    Mail.Image.png(image, filename: "Screenshot.png")
    Mail.Content.alternative("**End** of mail btw.", html: "<b>End</b> of mail btw.")
    Mail.Attachment(attachment, mimeType: "application/pdf")
}

try await client.sendMail(mail)
```

### Community

[Join our Discord](https://discord.gg/H6799jh) for any questions and friendly banter.

If you need hands-on support on your projects, our team is available at [hello@unbeatable.software](mailto:hello@unbeatable.software).
