import Foundation
import XCTest
@testable import ShopCore

final class WebDAVTransportTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        StubURLProtocol.handler = nil
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: configuration)
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        session.invalidateAndCancel()
        session = nil
        super.tearDown()
    }

    func testFetchDecodesSnapshotAndReturnsETag() async throws {
        let snapshot = makeSnapshot()
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.absoluteString, "https://dav.example.com/remote.php/dav/shop_sync.json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Basic dXNlcjpwYXNz")
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            return (.http(status: 200, url: try XCTUnwrap(request.url), headers: ["ETag": "\"v3\""]), try encoder.encode(snapshot))
        }

        let remote = try await makeTransport(serverURL: "https://dav.example.com/remote.php/dav/").fetch()

        XCTAssertEqual(remote?.snapshot, snapshot)
        XCTAssertEqual(remote?.etag, "\"v3\"")
    }

    func testFetchReturnsNilForNotFound() async throws {
        StubURLProtocol.handler = { request in
            (.http(status: 404, url: try XCTUnwrap(request.url)), Data())
        }

        let snapshot = try await makeTransport().fetch()
        XCTAssertNil(snapshot)
    }

    func testPutCreateSendsIfNoneMatch() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), "*")
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-Match"), nil)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            return (.http(status: 201, url: try XCTUnwrap(request.url), headers: ["ETag": "\"v1\""]), Data())
        }

        let etag = try await makeTransport().put(makeSnapshot(), precondition: .create)

        XCTAssertEqual(etag, "\"v1\"")
    }

    func testPutUpdateSendsETag() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-Match"), "\"v3\"")
            return (.http(status: 204, url: try XCTUnwrap(request.url)), Data())
        }

        let etag = try await makeTransport().put(makeSnapshot(), precondition: .etag("\"v3\""))
        XCTAssertNil(etag)
    }

    func testUnauthorizedMapsToTypedError() async throws {
        StubURLProtocol.handler = { request in
            (.http(status: 401, url: try XCTUnwrap(request.url)), Data())
        }

        await assertError(.unauthorized) {
            _ = try await self.makeTransport().fetch()
        }
    }

    func testPreconditionFailureMapsToTypedError() async throws {
        StubURLProtocol.handler = { request in
            (.http(status: 412, url: try XCTUnwrap(request.url)), Data())
        }

        await assertError(.preconditionFailed) {
            _ = try await self.makeTransport().put(self.makeSnapshot(), precondition: .etag("\"old\""))
        }
    }

    func testTimeoutMapsToNetworkError() async throws {
        StubURLProtocol.handler = { _ in throw URLError(.timedOut) }

        await assertError(.network(.timedOut)) {
            _ = try await self.makeTransport().fetch()
        }
    }

    func testNetworkFailureMapsToTypedError() async throws {
        StubURLProtocol.handler = { _ in throw URLError(.cannotConnectToHost) }

        await assertError(.network(.cannotConnectToHost)) {
            _ = try await self.makeTransport().fetch()
        }
    }

    func testNonHTTPResponseMapsToInvalidResponse() async throws {
        StubURLProtocol.handler = { request in
            (URLResponse(url: try XCTUnwrap(request.url), mimeType: nil, expectedContentLength: 0, textEncodingName: nil), Data())
        }

        await assertError(.invalidResponse) {
            _ = try await self.makeTransport().fetch()
        }
    }

    func testMalformedJSONMapsToDecodingError() async throws {
        StubURLProtocol.handler = { request in
            (.http(status: 200, url: try XCTUnwrap(request.url)), Data("not json".utf8))
        }

        await assertError(.decoding) {
            _ = try await self.makeTransport().fetch()
        }
    }

    func testRejectsInsecureURLsUnlessExplicitlyAllowed() throws {
        XCTAssertThrowsError(try WebDAVTransport(
            serverURL: "http://dav.example.com",
            username: "user",
            password: "pass",
            session: session
        )) { XCTAssertEqual($0 as? WebDAVError, .insecureURL) }

        XCTAssertNoThrow(try WebDAVTransport(
            serverURL: "http://dav.example.com",
            username: "user",
            password: "pass",
            session: session,
            allowsInsecureHTTP: true
        ))
    }

    private func makeTransport(serverURL: String = "https://dav.example.com/webdav") throws -> WebDAVTransport {
        try WebDAVTransport(serverURL: serverURL, username: "user", password: "pass", session: session)
    }

    private func makeSnapshot() -> SyncSnapshot {
        SyncSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_000),
            items: [],
            tags: []
        )
    }

    private func assertError(
        _ expected: WebDAVError,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected \(expected)")
        } catch {
            XCTAssertEqual(error as? WebDAVError, expected)
        }
    }
}

private final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (URLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let (response, data) = try XCTUnwrap(Self.handler)(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension URLResponse {
    static func http(status: Int, url: URL, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
    }
}
