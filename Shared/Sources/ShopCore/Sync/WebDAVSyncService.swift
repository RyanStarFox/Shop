import Foundation

#if os(iOS) || os(macOS)
@MainActor
public final class WebDAVSyncService: ObservableObject {
    @Published public var isConfigured = false
    @Published public var isSyncing = false
    @Published public var lastSyncDate: Date?
    @Published public var error: String?

    private var serverURL: URL?
    private var username: String?
    private var password: String?
    private var dataStore: DataStore?
    private let syncFileName = "shop_sync.json"

    public init() {}

    public func configure(serverURL: String, username: String, password: String) {
        self.serverURL = URL(string: serverURL)
        self.username = username
        self.password = password
        isConfigured = true
    }

    public func configure(with dataStore: DataStore) {
        self.dataStore = dataStore
    }

    public func clearConfiguration() {
        serverURL = nil
        username = nil
        password = nil
        isConfigured = false
    }

    private func authHeader() -> String? {
        guard let username, let password else { return nil }
        let credential = "\(username):\(password)"
        guard let data = credential.data(using: .utf8) else { return nil }
        return "Basic \(data.base64EncodedString())"
    }

    // MARK: - Upload

    public func upload() async {
        guard isConfigured, let serverURL, let data = dataStore?.exportData() else {
            error = NSLocalizedString("webdav.not_configured", comment: "")
            return
        }
        isSyncing = true
        error = nil
        defer { isSyncing = false }

        let fileURL = serverURL.appendingPathComponent(syncFileName)
        var request = URLRequest(url: fileURL)
        request.httpMethod = "PUT"
        request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let auth = authHeader() {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                error = NSLocalizedString("webdav.upload_failed", comment: "")
                return
            }
            lastSyncDate = Date()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Download

    public func download() async {
        guard isConfigured, let serverURL else {
            error = NSLocalizedString("webdav.not_configured", comment: "")
            return
        }
        isSyncing = true
        error = nil
        defer { isSyncing = false }

        let fileURL = serverURL.appendingPathComponent(syncFileName)
        var request = URLRequest(url: fileURL)
        request.httpMethod = "GET"
        if let auth = authHeader() {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                error = NSLocalizedString("webdav.download_failed", comment: "")
                return
            }
            if httpResponse.statusCode == 404 {
                // File doesn't exist yet — first sync, upload ours
                await upload()
                return
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                error = NSLocalizedString("webdav.download_failed", comment: "")
                return
            }
            dataStore?.importData(data)
            lastSyncDate = Date()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Auto-sync

    public func autoSync() async {
        guard isConfigured else { return }

        // Download first, merge, then upload
        await download()

        // After merging, push our changes
        if error == nil {
            await upload()
        }
    }
}
#endif
