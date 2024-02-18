extension Mail {
    public struct Disposition: Sendable {
        enum _Disposition: String, Sendable {
            case inline
            case attachment
        }

        let disposition: _Disposition

        public static let `inline` = Disposition(disposition: .inline)
        public static let attachment = Disposition(disposition: .attachment)
    }
}
