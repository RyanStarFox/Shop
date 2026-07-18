import SwiftUI
import SwiftData
import WidgetKit
import BackgroundTasks
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
    @AppStorage("webdav_path") private var webdavPath = ""
    @AppStorage("appearance_mode") private var appearanceMode = AppearancePreference.system.rawValue
    @AppStorage("has_seen_onboarding") private var hasSeenOnboarding = false
    @State private var showOnboarding = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        ShopBackgroundRefresh.register()
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
                .tint(ShopTheme.brandColor)
                .preferredColorScheme(AppearancePreference(storageValue: appearanceMode).colorScheme)
                .onAppear {
                    ShopBackgroundSyncRunner.shared.configure(
                        dataStore: dataStore,
                        syncCoordinator: syncCoordinator
                    )
                    watchSync.configure(with: dataStore)
                    webdavSync.migrateLegacyPasswordIfNeeded(
                        serverURL: webdavServer,
                        username: webdavUsername,
                        folderPath: webdavPath
                    )
                    webdavSync.restoreCredentials(
                        serverURL: webdavServer,
                        username: webdavUsername,
                        folderPath: webdavPath
                    )
                    dataStore.applyPendingWidgetMutations()
                    dataStore.publishWidgetSnapshot()
                    WidgetCenter.shared.reloadAllTimelines()
                    _ = dataStore.addLocalMutationObserver {
                        dataStore.publishWidgetSnapshot()
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                    if !hasSeenOnboarding {
                        showOnboarding = true
                    }
                    ShopBackgroundRefresh.schedule()
                    Task {
                        await syncCoordinator.syncNowIfConfigured()
                        if syncCoordinator.status.failureMessage == nil {
                            WidgetSnapshotStore.clearNeedsSync()
                        }
                        dataStore.pruneExpiredData()
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        dataStore.applyPendingWidgetMutations()
                        dataStore.publishWidgetSnapshot()
                        WidgetCenter.shared.reloadAllTimelines()
                        watchSync.requestLatestSnapshot()
                        watchSync.sendLatestSnapshot()
                        Task {
                            await syncCoordinator.syncNowIfConfigured()
                            if syncCoordinator.status.failureMessage == nil {
                                WidgetSnapshotStore.clearNeedsSync()
                            }
                            dataStore.pruneExpiredData()
                        }
                        ShopBackgroundRefresh.schedule()
                    case .background:
                        if WidgetSnapshotStore.loadNeedsSync() {
                            ShopBackgroundRefresh.scheduleSoon()
                        } else {
                            ShopBackgroundRefresh.schedule()
                        }
                    default:
                        break
                    }
                }
                .onOpenURL { url in
                    guard url.scheme == "shop", url.host == "add" else { return }
                    NotificationCenter.default.post(name: .shopAddFromWidget, object: nil)
                }
                .onReceive(NotificationCenter.default.publisher(for: .shopShowOnboarding)) { _ in
                    showOnboarding = true
                }
                .sheet(isPresented: $showOnboarding) {
                    OnboardingView(style: .phone) {
                        hasSeenOnboarding = true
                        showOnboarding = false
                    }
                    .presentationDetents([.large])
                }
        }
        .modelContainer(dataStore.modelContainer)
    }
}

extension Notification.Name {
    static let shopShowOnboarding = Notification.Name("shopShowOnboarding")
    static let shopAddFromWidget = Notification.Name("shopAddFromWidget")
}
