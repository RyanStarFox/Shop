import SwiftUI
import SwiftData
import ShopCore

@main
struct ShopApp: App {
    @StateObject private var dataStore: DataStore
    @StateObject private var wifiSync = WiFiSyncService()
    @StateObject private var webdavSync: WebDAVSyncService
    @StateObject private var syncCoordinator: SyncCoordinator
    @AppStorage("webdav_server") private var webdavServer = ""
    @AppStorage("webdav_username") private var webdavUsername = ""

    init() {
        let store = DataStore()
        let coordinator = SyncCoordinator(dataStore: store)
        _dataStore = StateObject(wrappedValue: store)
        _syncCoordinator = StateObject(wrappedValue: coordinator)
        _webdavSync = StateObject(wrappedValue: WebDAVSyncService(coordinator: coordinator))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dataStore)
                .environmentObject(wifiSync)
                .environmentObject(webdavSync)
                .environmentObject(syncCoordinator)
                .tint(.accentColor)
                .onAppear {
                    wifiSync.configure(with: dataStore)
                    webdavSync.migrateLegacyPasswordIfNeeded(
                        serverURL: webdavServer,
                        username: webdavUsername
                    )
                    webdavSync.restoreCredentials(
                        serverURL: webdavServer,
                        username: webdavUsername
                    )
                }
        }
        .modelContainer(dataStore.modelContainer)
    }
}
