@resultBuilder
public struct MailBodyBuilder {
    
    /// Creates the email contents body.
    public static func buildBlock(_ components: MailContentConvertible...) -> Mail.Content {
        let blocks = components.flatMap(\.content.blocks)

        if blocks.count == 1 {
            return .single(blocks[0])
        } else {
            return .multiple(blocks)
        }
    }
    
    /// Creates the email contents body bases on an array, this will allow you to construct the body based on wild elements.
    public static func buildBlock(_ components: [MailContentConvertible]) -> Mail.Content {

        let blocks = components.flatMap(\.content.blocks)

        if blocks.count == 1 {
            return .single(blocks[0])
        } else {
            return .multiple(blocks)
        }
    }
}
