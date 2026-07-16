import Foundation

extension WebDAVError {
    /// Friendly localized summary for UI.
    public var friendlyMessage: String {
        switch self {
        case .unauthorized:
            ShopStrings.webdavUnauthorized
        case .preconditionFailed:
            ShopStrings.webdavPreconditionFailed
        case .network:
            ShopStrings.webdavNetworkFailed
        case .invalidURL:
            ShopStrings.webdavInvalidServer
        case .insecureURL:
            ShopStrings.webdavInsecureServer
        case .notFound:
            ShopStrings.webdavNotFound
        case .httpStatus(let code):
            ShopStrings.webdavHTTPFailed(code)
        case .invalidResponse:
            ShopStrings.webdavInvalidResponse
        case .decoding:
            ShopStrings.webdavDecodingFailed
        }
    }

    /// Machine-oriented detail (status codes, URLError raw values, etc.).
    public var technicalDetail: String {
        switch self {
        case .unauthorized:
            "HTTP 401 Unauthorized"
        case .preconditionFailed:
            "HTTP 412 Precondition Failed"
        case .network(let code):
            "URLError \(code.rawValue) (\(Self.urlErrorLabel(code)))"
        case .invalidURL:
            "invalidURL"
        case .insecureURL:
            "insecureURL (HTTPS required)"
        case .notFound:
            "HTTP 404 Not Found"
        case .httpStatus(let code):
            "HTTP \(code)"
        case .invalidResponse:
            "invalidResponse (non-HTTP URLResponse)"
        case .decoding:
            "JSON decoding failed"
        }
    }

    /// Friendly Chinese / localized text plus raw technical detail.
    public var userFacingMessage: String {
        "\(friendlyMessage)\n\(ShopStrings.webdavErrorDetailPrefix)\(technicalDetail)"
    }

    private static func urlErrorLabel(_ code: URLError.Code) -> String {
        switch code {
        case .timedOut: "timedOut"
        case .cannotFindHost: "cannotFindHost"
        case .cannotConnectToHost: "cannotConnectToHost"
        case .networkConnectionLost: "networkConnectionLost"
        case .notConnectedToInternet: "notConnectedToInternet"
        case .dnsLookupFailed: "dnsLookupFailed"
        case .secureConnectionFailed: "secureConnectionFailed"
        case .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
            "serverCertificateProblem"
        case .appTransportSecurityRequiresSecureConnection:
            "ATSRequiresHTTPS"
        case .badURL: "badURL"
        case .unsupportedURL: "unsupportedURL"
        case .unknown: "unknown"
        default: String(describing: code)
        }
    }
}

extension WebDAVError {
    public var isRecoverable: Bool {
        switch self {
        case .preconditionFailed, .network, .httpStatus:
            true
        case .invalidURL, .insecureURL, .unauthorized, .notFound, .invalidResponse, .decoding:
            false
        }
    }
}
