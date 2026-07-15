import SwiftUI
import SwiftData
import ShopCore

@main
struct ShopMacApp: App {
    @StateObject private var dataStore: ShopCore.DataStore
    @StateObject private var undoCoordinator: UndoCoordinator
    @StateObject private var webdavSync: WebDAVSyncService
    @StateObject private var syncCoordinator: SyncCoordinator

    @AppStorage("webdav_server") private var webdavServer = ""
    @AppStorage("webdav_username") private var webdavUsername = ""
    @AppStorage("appearance_mode") private var appearanceMode = AppearancePreference.system.rawValue

    init() {
        let store = ShopCore.DataStore()
        let coordinator = SyncCoordinator(dataStore: store)
        let undo = UndoCoordinator(performMutation: { mutation in
            try store.performUndoMutation(mutation)
        })
        _dataStore = StateObject(wrappedValue: store)
        _undoCoordinator = StateObject(wrappedValue: undo)
        _syncCoordinator = StateObject(wrappedValue: coordinator)
        _webdavSync = StateObject(wrappedValue: WebDAVSyncService(coordinator: coordinator))
    }

    var body: some Scene {
        WindowGroup {
            MacContentView()
                .environmentObject(dataStore)
                .environmentObject(undoCoordinator)
                .environmentObject(webdavSync)
                .environmentObject(syncCoordinator)
                .tint(ShopTheme.naturalGreen)
                .preferredColorScheme(AppearancePreference(storageValue: appearanceMode).colorScheme)
                .frame(minWidth: 720, idealWidth: 960, minHeight: 520, idealHeight: 700)
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
        .modelContainer(dataStore.modelContainer)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 960, height: 700)

        Settings {
            MacSettingsView()
                .environmentObject(dataStore)
                .environmentObject(undoCoordinator)
                .environmentObject(webdavSync)
                .environmentObject(syncCoordinator)
                .preferredColorScheme(AppearancePreference(storageValue: appearanceMode).colorScheme)
        }
    }
}
