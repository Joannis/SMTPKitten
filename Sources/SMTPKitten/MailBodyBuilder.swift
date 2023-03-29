@resultBuilder
public struct MailBodyBuilder {
    public static func buildBlock(_ components: MailContentConvertible...) -> Mail.Content {
        let blocks = components.flatMap(\.content.blocks)

        if blocks.count == 1 {
            return .single(blocks[0])
        } else {
            return .multiple(blocks)
        }
    }
}
