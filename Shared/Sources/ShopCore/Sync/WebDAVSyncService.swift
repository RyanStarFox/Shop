import Foundation

#if os(iOS) || os(macOS)
@MainActor
public final class WebDAVSyncService: ObservableObject {
    @Published public var isConfigured = false
    @Published public private(set) var configurationError: String?
    /// Last resolved `shop_sync.json` URL for diagnostics.
    @Published public private(set) var resolvedFileURL: String?

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
            resolvedFileURL = nil
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
                resolvedFileURL = nil
                configurationError = """
                \(ShopStrings.webdavMissingPassword)
                \(ShopStrings.webdavErrorDetailPrefix)missingKeychainPassword
                """
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
            resolvedFileURL = nil
            configurationError = localizedMessage(for: error, serverURL: serverURL, folderPath: folderPath)
            throw error
        }
    }

    public func restoreCredentials(serverURL: String, username: String, folderPath: String = "") {
        guard !serverURL.isEmpty, !username.isEmpty else {
            transport = nil
            coordinator?.configure(transport: nil)
            isConfigured = false
            resolvedFileURL = nil
            return
        }
        do {
            guard let password = try keychain.password(username: username, serverURL: serverURL) else {
                transport = nil
                coordinator?.configure(transport: nil)
                isConfigured = false
                resolvedFileURL = nil
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
            resolvedFileURL = nil
            configurationError = localizedMessage(for: error, serverURL: serverURL, folderPath: folderPath)
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
            configurationError = localizedMessage(for: error, serverURL: serverURL, folderPath: folderPath)
        }
    }

    public func clearCredentials(serverURL: String, username: String) throws {
        try keychain.deletePassword(username: username, serverURL: serverURL)
        transport = nil
        coordinator?.configure(transport: nil)
        isConfigured = false
        resolvedFileURL = nil
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
        let built = try WebDAVTransport(
            serverURL: serverURL,
            username: username,
            password: password,
            folderPath: folderPath
        )
        transport = built
        resolvedFileURL = built.syncFileURLString
        coordinator?.configure(transport: transport)
        isConfigured = true
        configurationError = nil
    }

    private func localizedMessage(
        for error: Error,
        serverURL: String,
        folderPath: String
    ) -> String {
        var message: String
        if let error = error as? WebDAVError {
            message = error.userFacingMessage
        } else {
            message = """
            \(ShopStrings.webdavSyncFailed)
            \(ShopStrings.webdavErrorDetailPrefix)\(error.localizedDescription)
            """
        }
        if let url = try? WebDAVTransport.makeSyncFileURL(
            serverURL: serverURL,
            folderPath: folderPath
        ).absoluteString {
            message += "\n\(ShopStrings.webdavTargetURLPrefix)\(url)"
        }
        return message
    }
}
#endif
