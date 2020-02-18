# SMTPKitten

Creat

```swift
let mail = Mail(
    from: MailUser(name: "My Mailer", email: "noreply@example.com"),
    to: [MailUser(name: "John Doe", email: "john.doe@example.com")],
    subject: "Welcome to our app!",
    contentType: .plain,
    text: "Welcome to our app, you're all set up & stuff."
)

SMTPClient.connect(
    hostname: "smtp.example.com",
    ssl: .startTLS(configuration: .default)
).flatMap { client in
    client.login(
        user: "noreply@example.com",
        password: "pas$w0rd"
    ).flatMap {
        client.sendMail(mail)
    }
}
```
