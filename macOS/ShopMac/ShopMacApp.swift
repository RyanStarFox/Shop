import SwiftUI
import ShopCore

@main
struct ShopMacApp: App {
    @StateObject private var dataStore: DataStore
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
            MacContentView()
                .environmentObject(dataStore)
                .environmentObject(webdavSync)
                .environmentObject(syncCoordinator)
                .frame(minWidth: 400, idealWidth: 480, minHeight: 500, idealHeight: 700)
                .onAppear {
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
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        Settings {
            MacSettingsView()
                .environmentObject(dataStore)
                .environmentObject(webdavSync)
                .environmentObject(syncCoordinator)
        }
    }
}
