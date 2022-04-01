# SMTPKitten

How to send a simple email using SMTP Kitten:

```swift
// Create Mail instance
let mail = Mail(
    from: MailUser(name: "My Mailer", email: "noreply@example.com"),
    to: [MailUser(name: "John Doe", email: "john.doe@example.com")],
    subject: "Welcome to our app!",
    contentType: .plain,
    text: "Welcome to our app, you're all set up & stuff."
)

// Connect to the SMTP server
let client = try await SMTPClient.connect(
    hostname: "smtp.example.com",
    ssl: .startTLS(configuration: .default)
)

// Login using your credentials
try await client.login(user: "noreply@example.com", password: "pas$w0rd")

// Send out mails 🎉
try await client.sendMail(mail)
```
