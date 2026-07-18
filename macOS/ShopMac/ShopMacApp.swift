import SwiftUI
import SwiftData
import AppKit
import WidgetKit
import ShopCore

@main
struct ShopMacApp: App {
    @StateObject private var dataStore: ShopCore.DataStore
    @StateObject private var undoCoordinator: UndoCoordinator
    @StateObject private var webdavSync: WebDAVSyncService
    @StateObject private var syncCoordinator: SyncCoordinator

    @AppStorage("webdav_server") private var webdavServer = ""
    @AppStorage("webdav_username") private var webdavUsername = ""
    @AppStorage("webdav_path") private var webdavPath = ""
    @AppStorage("appearance_mode") private var appearanceMode = AppearancePreference.system.rawValue
    @AppStorage("has_seen_onboarding") private var hasSeenOnboarding = false
    @State private var showOnboarding = false
    @State private var backgroundActivity: NSBackgroundActivityScheduler?
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
            MacContentView()
                .environmentObject(dataStore)
                .environmentObject(undoCoordinator)
                .environmentObject(webdavSync)
                .environmentObject(syncCoordinator)
                .tint(ShopTheme.brandColor)
                .preferredColorScheme(AppearancePreference(storageValue: appearanceMode).colorScheme)
                .frame(minWidth: 720, idealWidth: 960, minHeight: 520, idealHeight: 700)
                .onAppear {
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
                    startBackgroundActivityIfNeeded()
                    Task {
                        await syncCoordinator.syncNowIfConfigured()
                        if syncCoordinator.status.failureMessage == nil {
                            WidgetSnapshotStore.clearNeedsSync()
                        }
                        dataStore.pruneExpiredData()
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    dataStore.applyPendingWidgetMutations()
                    dataStore.publishWidgetSnapshot()
                    WidgetCenter.shared.reloadAllTimelines()
                    Task {
                        await syncCoordinator.syncNowIfConfigured()
                        if syncCoordinator.status.failureMessage == nil {
                            WidgetSnapshotStore.clearNeedsSync()
                        }
                        dataStore.pruneExpiredData()
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
                    OnboardingView(style: .mac) {
                        hasSeenOnboarding = true
                        showOnboarding = false
                    }
                    .frame(width: 480, height: 420)
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

    private func startBackgroundActivityIfNeeded() {
        guard backgroundActivity == nil else { return }
        let activity = NSBackgroundActivityScheduler(identifier: "com.ryanstarfox.shop.mac.refresh")
        activity.repeats = true
        activity.qualityOfService = .utility
        // Best-effort ~hourly; system may delay. Night still uses this cadence while the app stays open.
        activity.interval = 3600
        activity.schedule { [weak dataStore, weak syncCoordinator] completion in
            Task { @MainActor in
                guard let dataStore, let syncCoordinator else {
                    completion(.finished)
                    return
                }
                dataStore.applyPendingWidgetMutations()
                await syncCoordinator.syncNowIfConfigured()
                dataStore.publishWidgetSnapshot()
                WidgetCenter.shared.reloadAllTimelines()
                if syncCoordinator.status.failureMessage == nil {
                    WidgetSnapshotStore.clearNeedsSync()
                }
                completion(.finished)
            }
        }
        backgroundActivity = activity
    }
}

extension Notification.Name {
    static let shopShowOnboarding = Notification.Name("shopShowOnboarding")
    static let shopAddFromWidget = Notification.Name("shopAddFromWidget")
}
