import NIOSSL

public struct SMTPSSLConfiguration {
    internal let configuration: _Configuration
    
    public static var `default`: SMTPSSLConfiguration {
        return SMTPSSLConfiguration(configuration: .default)
    }
    
    public static func customRoot(path: String) -> SMTPSSLConfiguration {
        return SMTPSSLConfiguration(configuration: .customRoot(path: path))
    }
    
    public static func custom(configuration: TLSConfiguration) -> SMTPSSLConfiguration {
        return SMTPSSLConfiguration(configuration: .custom(configuration))
    }

    internal enum _Configuration {
        case `default`
        case customRoot(path: String)
        case custom(TLSConfiguration)
        
        internal func makeTlsConfiguration() -> TLSConfiguration {
            switch self {
            case .default:
                return TLSConfiguration.clientDefault
            case .customRoot(let path):
                var tlsConfig = TLSConfiguration.makeClientConfiguration()
                tlsConfig.trustRoots = .file(path)
                return tlsConfig
            case .custom(let config):
                return config
            }
        }
    }
}

/// The mode that the SMTP client should use for SSL. This can be either `startTLS`, `tls` or `insecure`.
public struct SMTPSSLMode {
    internal enum _Mode {
        /// The SMTP client should use the `STARTTLS` command to upgrade the connection to SSL.
        case startTLS(configuration: SMTPSSLConfiguration)

        /// The SMTP client should use SSL from the start.
        case tls(configuration: SMTPSSLConfiguration)

        /// The SMTP client should not use SSL.
        case insecure
    }

    internal let mode: _Mode

    public static var insecure: SMTPSSLMode {
        return SMTPSSLMode(mode: .insecure)
    }

    public static func startTLS(configuration: SMTPSSLConfiguration = .default) -> SMTPSSLMode {
        return SMTPSSLMode(mode: .startTLS(configuration: configuration))
    }

    public static func tls(configuration: SMTPSSLConfiguration = .default) -> SMTPSSLMode {
        return SMTPSSLMode(mode: .tls(configuration: configuration))
    }
}
