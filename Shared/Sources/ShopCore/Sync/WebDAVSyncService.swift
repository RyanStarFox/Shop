import Foundation

#if os(iOS) || os(macOS)
@MainActor
public final class WebDAVSyncService: ObservableObject {
    @Published public var isConfigured = false
    @Published public var isSyncing = false
    @Published public var lastSyncDate: Date?
    @Published public var error: String?

    private let keychain: KeychainStore
    private let now: () -> Date
    private var transport: (any WebDAVTransporting)?
    private var dataStore: DataStore?

    public init(
        keychain: KeychainStore = KeychainStore(),
        transport: (any WebDAVTransporting)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.keychain = keychain
        self.transport = transport
        self.now = now
        isConfigured = transport != nil
    }

    public func configure(with dataStore: DataStore) {
        self.dataStore = dataStore
    }

    public func saveCredentials(serverURL: String, username: String, password: String) throws {
        guard !serverURL.isEmpty, !username.isEmpty else {
            isConfigured = false
            error = ShopStrings.webdavNotConfigured
            return
        }

        do {
            if !password.isEmpty {
                try keychain.setPassword(password, username: username, serverURL: serverURL)
            }
            guard let storedPassword = try keychain.password(username: username, serverURL: serverURL) else {
                transport = nil
                isConfigured = false
                error = ShopStrings.webdavNotConfigured
                return
            }
            try configureTransport(serverURL: serverURL, username: username, password: storedPassword)
        } catch {
            transport = nil
            isConfigured = false
            self.error = localizedMessage(for: error)
            throw error
        }
    }

    public func restoreCredentials(serverURL: String, username: String) {
        guard !serverURL.isEmpty, !username.isEmpty else {
            isConfigured = false
            return
        }
        do {
            guard let password = try keychain.password(username: username, serverURL: serverURL) else {
                transport = nil
                isConfigured = false
                return
            }
            try configureTransport(serverURL: serverURL, username: username, password: password)
        } catch {
            transport = nil
            isConfigured = false
            self.error = localizedMessage(for: error)
        }
    }

    public func migrateLegacyPasswordIfNeeded(
        serverURL: String,
        username: String,
        defaults: UserDefaults = .standard
    ) {
        guard let legacyPassword = defaults.string(forKey: "webdav_password"),
              !serverURL.isEmpty,
              !username.isEmpty else {
            return
        }

        do {
            try keychain.setPassword(legacyPassword, username: username, serverURL: serverURL)
            defaults.removeObject(forKey: "webdav_password")
            try configureTransport(serverURL: serverURL, username: username, password: legacyPassword)
        } catch {
            self.error = localizedMessage(for: error)
        }
    }

    public func clearCredentials(serverURL: String, username: String) throws {
        try keychain.deletePassword(username: username, serverURL: serverURL)
        transport = nil
        isConfigured = false
        error = nil
    }

    public func syncNow() async {
        guard let transport, let dataStore else {
            error = ShopStrings.webdavNotConfigured
            return
        }

        isSyncing = true
        error = nil
        defer { isSyncing = false }

        do {
            let remote = try await transport.fetch()
            if let remote {
                try dataStore.shoppingStore.apply(snapshot: remote.snapshot)
                dataStore.fetchData()
            }

            let mergedSnapshot = try dataStore.shoppingStore.makeSnapshot(now: now())
            let precondition: WebDAVPrecondition
            if let remote {
                guard let etag = remote.etag else {
                    throw WebDAVError.invalidResponse
                }
                precondition = .etag(etag)
            } else {
                precondition = .create
            }
            _ = try await transport.put(mergedSnapshot, precondition: precondition)
            lastSyncDate = now()
        } catch {
            self.error = localizedMessage(for: error)
        }
    }

    public func autoSync() async {
        await syncNow()
    }

    private func configureTransport(serverURL: String, username: String, password: String) throws {
        transport = try WebDAVTransport(
            serverURL: serverURL,
            username: username,
            password: password
        )
        isConfigured = true
        error = nil
    }

    private func localizedMessage(for error: Error) -> String {
        guard let error = error as? WebDAVError else {
            return ShopStrings.webdavSyncFailed
        }
        switch error {
        case .unauthorized:
            return ShopStrings.webdavUnauthorized
        case .preconditionFailed:
            return ShopStrings.webdavPreconditionFailed
        case .network:
            return ShopStrings.webdavNetworkFailed
        case .invalidURL, .insecureURL:
            return ShopStrings.webdavInvalidServer
        case .notFound, .invalidResponse, .decoding:
            return ShopStrings.webdavSyncFailed
        }
    }
}
#endif
