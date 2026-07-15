import Foundation

public enum WebDAVError: Error, Equatable, Sendable {
    case invalidURL
    case insecureURL
    case unauthorized
    case notFound
    case preconditionFailed
    case invalidResponse
    case decoding
    case network(URLError.Code)

    public var isRecoverable: Bool {
        switch self {
        case .preconditionFailed, .network:
            true
        case .invalidURL, .insecureURL, .unauthorized, .notFound, .invalidResponse, .decoding:
            false
        }
    }
}

public struct RemoteSnapshot: Equatable, Sendable {
    public let snapshot: SyncSnapshot
    public let etag: String?

    public init(snapshot: SyncSnapshot, etag: String?) {
        self.snapshot = snapshot
        self.etag = etag
    }
}

public enum WebDAVPrecondition: Equatable, Sendable {
    case none
    case create
    case etag(String)
}

public protocol WebDAVTransporting: Sendable {
    func fetch() async throws -> RemoteSnapshot?
    func put(_ snapshot: SyncSnapshot, precondition: WebDAVPrecondition) async throws -> String?
}

public final class WebDAVTransport: WebDAVTransporting, @unchecked Sendable {
    private let fileURL: URL
    private let authorizationHeader: String
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        serverURL: String,
        username: String,
        password: String,
        folderPath: String = "",
        session: URLSession = .shared,
        allowsInsecureHTTP: Bool = false
    ) throws {
        self.fileURL = try Self.makeSyncFileURL(
            serverURL: serverURL,
            folderPath: folderPath,
            allowsInsecureHTTP: allowsInsecureHTTP
        )
        self.authorizationHeader = Self.makeAuthorizationHeader(username: username, password: password)
        self.session = session

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    /// Builds `…/folder/shop_sync.json` from a base server URL and optional folder path.
    public static func makeSyncFileURL(
        serverURL: String,
        folderPath: String = "",
        allowsInsecureHTTP: Bool = false
    ) throws -> URL {
        var normalizedServer = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedServer.isEmpty else {
            throw WebDAVError.invalidURL
        }
        if !normalizedServer.hasSuffix("/") {
            normalizedServer += "/"
        }

        var normalizedFolder = folderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        while normalizedFolder.hasPrefix("/") {
            normalizedFolder.removeFirst()
        }
        while normalizedFolder.hasSuffix("/") {
            normalizedFolder.removeLast()
        }

        let directoryURLString: String
        if normalizedFolder.isEmpty {
            directoryURLString = normalizedServer
        } else {
            directoryURLString = normalizedServer + normalizedFolder + "/"
        }

        guard let directoryURL = URL(string: directoryURLString),
              let scheme = directoryURL.scheme?.lowercased(),
              directoryURL.host != nil,
              scheme == "https" || scheme == "http" else {
            throw WebDAVError.invalidURL
        }
        guard scheme == "https" || allowsInsecureHTTP else {
            throw WebDAVError.insecureURL
        }

        return directoryURL.appendingPathComponent("shop_sync.json", isDirectory: false)
    }

    public func fetch() async throws -> RemoteSnapshot? {
        let request = makeRequest(method: "GET")
        let (data, response) = try await perform(request)
        let httpResponse = try validate(response)

        switch httpResponse.statusCode {
        case 200...299:
            do {
                return RemoteSnapshot(
                    snapshot: try decoder.decode(SyncSnapshot.self, from: data),
                    etag: httpResponse.value(forHTTPHeaderField: "ETag")
                )
            } catch {
                throw WebDAVError.decoding
            }
        case 401:
            throw WebDAVError.unauthorized
        case 404:
            return nil
        case 412:
            throw WebDAVError.preconditionFailed
        default:
            throw WebDAVError.invalidResponse
        }
    }

    public func put(_ snapshot: SyncSnapshot, precondition: WebDAVPrecondition) async throws -> String? {
        var request = makeRequest(method: "PUT")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        switch precondition {
        case .none:
            break
        case .create:
            request.setValue("*", forHTTPHeaderField: "If-None-Match")
        case let .etag(etag):
            request.setValue(etag, forHTTPHeaderField: "If-Match")
        }

        do {
            request.httpBody = try encoder.encode(snapshot)
        } catch {
            throw WebDAVError.invalidResponse
        }

        let (_, response) = try await perform(request)
        let httpResponse = try validate(response)
        switch httpResponse.statusCode {
        case 200...299:
            return httpResponse.value(forHTTPHeaderField: "ETag")
        case 401:
            throw WebDAVError.unauthorized
        case 404:
            throw WebDAVError.notFound
        case 412:
            throw WebDAVError.preconditionFailed
        default:
            throw WebDAVError.invalidResponse
        }
    }

    private func makeRequest(method: String) -> URLRequest {
        var request = URLRequest(url: fileURL)
        request.httpMethod = method
        request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            throw WebDAVError.network(error.code)
        } catch {
            throw WebDAVError.network(.unknown)
        }
    }

    private func validate(_ response: URLResponse) throws -> HTTPURLResponse {
        guard let response = response as? HTTPURLResponse else {
            throw WebDAVError.invalidResponse
        }
        return response
    }

    private static func makeAuthorizationHeader(username: String, password: String) -> String {
        let credentials = "\(username):\(password)"
        return "Basic \(Data(credentials.utf8).base64EncodedString())"
    }
}
