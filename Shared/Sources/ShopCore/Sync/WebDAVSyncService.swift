import Foundation

#if os(iOS) || os(macOS)
@MainActor
public final class WebDAVSyncService: ObservableObject {
    @Published public var isConfigured = false
    @Published public private(set) var configurationError: String?

    public var isSyncing: Bool { coordinator?.status.isSyncing ?? false }
    public var lastSyncDate: Date? { coordinator?.status.lastSuccess }
    public var error: String? { configurationError ?? coordinator?.status.failureMessage }

    private let keychain: KeychainStore
    private let now: () -> Date
    private var transport: (any WebDAVTransporting)?
    private var coordinator: SyncCoordinator?

    public init(
        keychain: KeychainStore = KeychainStore(),
        transport: (any WebDAVTransporting)? = nil,
        coordinator: SyncCoordinator? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.keychain = keychain
        self.transport = transport
        self.coordinator = coordinator
        self.now = now
        isConfigured = transport != nil
        coordinator?.configure(transport: transport)
    }

    public func configure(with dataStore: DataStore) {
        if coordinator == nil {
            coordinator = SyncCoordinator(dataStore: dataStore, transport: transport, now: now)
        }
    }

    public func saveCredentials(
        serverURL: String,
        username: String,
        password: String,
        folderPath: String = ""
    ) throws {
        guard !serverURL.isEmpty, !username.isEmpty else {
            transport = nil
            coordinator?.configure(transport: nil)
            isConfigured = false
            configurationError = ShopStrings.webdavNotConfigured
            return
        }

        do {
            if !password.isEmpty {
                try keychain.setPassword(password, username: username, serverURL: serverURL)
            }
            guard let storedPassword = try keychain.password(username: username, serverURL: serverURL) else {
                transport = nil
                coordinator?.configure(transport: nil)
                isConfigured = false
                configurationError = ShopStrings.webdavNotConfigured
                return
            }
            try configureTransport(
                serverURL: serverURL,
                username: username,
                password: storedPassword,
                folderPath: folderPath
            )
        } catch {
            transport = nil
            coordinator?.configure(transport: nil)
            isConfigured = false
            configurationError = localizedMessage(for: error)
            throw error
        }
    }

    public func restoreCredentials(serverURL: String, username: String, folderPath: String = "") {
        guard !serverURL.isEmpty, !username.isEmpty else {
            transport = nil
            coordinator?.configure(transport: nil)
            isConfigured = false
            return
        }
        do {
            guard let password = try keychain.password(username: username, serverURL: serverURL) else {
                transport = nil
                coordinator?.configure(transport: nil)
                isConfigured = false
                return
            }
            try configureTransport(
                serverURL: serverURL,
                username: username,
                password: password,
                folderPath: folderPath
            )
        } catch {
            transport = nil
            coordinator?.configure(transport: nil)
            isConfigured = false
            configurationError = localizedMessage(for: error)
        }
    }

    public func migrateLegacyPasswordIfNeeded(
        serverURL: String,
        username: String,
        folderPath: String = "",
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
            try configureTransport(
                serverURL: serverURL,
                username: username,
                password: legacyPassword,
                folderPath: folderPath
            )
        } catch {
            configurationError = localizedMessage(for: error)
        }
    }

    public func clearCredentials(serverURL: String, username: String) throws {
        try keychain.deletePassword(username: username, serverURL: serverURL)
        transport = nil
        coordinator?.configure(transport: nil)
        isConfigured = false
        configurationError = nil
    }

    public func syncNow() async {
        guard let coordinator else {
            configurationError = ShopStrings.webdavNotConfigured
            return
        }
        configurationError = nil
        await coordinator.syncNow()
    }

    public func autoSync() async {
        await syncNow()
    }

    private func configureTransport(
        serverURL: String,
        username: String,
        password: String,
        folderPath: String
    ) throws {
        transport = try WebDAVTransport(
            serverURL: serverURL,
            username: username,
            password: password,
            folderPath: folderPath
        )
        coordinator?.configure(transport: transport)
        isConfigured = true
        configurationError = nil
    }

    private func localizedMessage(for error: Error) -> String {
        switch error as? WebDAVError {
        case .unauthorized:
            ShopStrings.webdavUnauthorized
        case .preconditionFailed:
            ShopStrings.webdavPreconditionFailed
        case .network:
            ShopStrings.webdavNetworkFailed
        case .invalidURL, .insecureURL:
            ShopStrings.webdavInvalidServer
        case .notFound, .invalidResponse, .decoding, .none:
            ShopStrings.webdavSyncFailed
        }
    }
}
#endif
