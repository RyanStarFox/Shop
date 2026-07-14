import Foundation

#if os(iOS) || os(macOS)
@MainActor
public final class WebDAVSyncService: ObservableObject {
    @Published public var isConfigured = false
    @Published public var error: String?

    private let keychain: KeychainStore

    public init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
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
            isConfigured = try keychain.password(username: username, serverURL: serverURL) != nil
            error = isConfigured ? nil : ShopStrings.webdavNotConfigured
        } catch {
            isConfigured = false
            self.error = ShopStrings.webdavNotConfigured
            throw error
        }
    }

    public func restoreCredentials(serverURL: String, username: String) {
        guard !serverURL.isEmpty, !username.isEmpty else {
            isConfigured = false
            return
        }
        do {
            isConfigured = try keychain.password(username: username, serverURL: serverURL) != nil
            error = nil
        } catch {
            isConfigured = false
            self.error = ShopStrings.webdavNotConfigured
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
            isConfigured = true
            error = nil
        } catch {
            self.error = ShopStrings.webdavNotConfigured
        }
    }

    public func clearCredentials(serverURL: String, username: String) throws {
        try keychain.deletePassword(username: username, serverURL: serverURL)
        isConfigured = false
        error = nil
    }
}
#endif
