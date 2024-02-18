@resultBuilder
public struct MailBodyBuilder {
    /// Creates the email contents body.
    public static func buildBlock(_ components: Mail.Content...) -> Mail.Content {
        let blocks = components.flatMap(\.content.blocks)

        if blocks.count == 1 {
            return .single(blocks[0])
        } else {
            return .multipart(blocks)
        }
    }
}
