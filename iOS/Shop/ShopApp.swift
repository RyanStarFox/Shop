import SwiftUI
import SwiftData
import ShopCore

@main
struct ShopApp: App {
    @StateObject private var dataStore: ShopCore.DataStore
    @StateObject private var undoCoordinator: UndoCoordinator
    @StateObject private var watchSync = WatchSyncService()
    @StateObject private var webdavSync: WebDAVSyncService
    @StateObject private var syncCoordinator: SyncCoordinator
    @AppStorage("webdav_server") private var webdavServer = ""
    @AppStorage("webdav_username") private var webdavUsername = ""
    @AppStorage("appearance_mode") private var appearanceMode = AppearancePreference.system.rawValue
    @Environment(\.scenePhase) private var scenePhase

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
            ContentView()
                .environmentObject(dataStore)
                .environmentObject(undoCoordinator)
                .environmentObject(watchSync)
                .environmentObject(webdavSync)
                .environmentObject(syncCoordinator)
                .tint(ShopTheme.naturalGreen)
                .preferredColorScheme(AppearancePreference(storageValue: appearanceMode).colorScheme)
                .onAppear {
                    watchSync.configure(with: dataStore)
                    webdavSync.migrateLegacyPasswordIfNeeded(
                        serverURL: webdavServer,
                        username: webdavUsername
                    )
                    webdavSync.restoreCredentials(
                        serverURL: webdavServer,
                        username: webdavUsername
                    )
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    watchSync.requestLatestSnapshot()
                    watchSync.sendLatestSnapshot()
                }
        }
        .modelContainer(dataStore.modelContainer)
    }
}
