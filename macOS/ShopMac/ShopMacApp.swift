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
    @AppStorage(ThemeAccent.storageKey) private var themeHex = ThemeAccent.defaultHex
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
                .tint(ThemeAccent.color(hex: themeHex))
                .environment(\.shopAccent, ThemeAccent.color(hex: themeHex))
                .macPreferredAppearance(appearanceMode)
                .id(appearanceMode)
                .frame(minWidth: 720, idealWidth: 960, minHeight: 520, idealHeight: 700)
                .onAppear {
                    applyMacAppearance()
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
                .onChange(of: appearanceMode) { _, _ in
                    applyMacAppearance()
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
                .tint(ThemeAccent.color(hex: themeHex))
                .environment(\.shopAccent, ThemeAccent.color(hex: themeHex))
                .macPreferredAppearance(appearanceMode)
                .id(appearanceMode)
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

    /// SwiftUI `preferredColorScheme(nil)` does not undo a previous light/dark
    /// override, so the content can stay light while the window chrome follows
    /// the system. Apply the choice to AppKit, and only set a SwiftUI scheme
    /// for an explicit light or dark preference.
    private func applyMacAppearance() {
        let preference = AppearancePreference(storageValue: appearanceMode)
        let appearance: NSAppearance? = switch preference {
        case .system:
            nil
        case .light:
            NSAppearance(named: .aqua)
        case .dark:
            NSAppearance(named: .darkAqua)
        }
        NSApp.appearance = appearance
        for window in NSApp.windows {
            window.appearance = appearance
        }
    }
}

extension Notification.Name {
    static let shopShowOnboarding = Notification.Name("shopShowOnboarding")
    static let shopAddFromWidget = Notification.Name("shopAddFromWidget")
}

private extension View {
    @ViewBuilder
    func macPreferredAppearance(_ storageValue: String) -> some View {
        switch AppearancePreference(storageValue: storageValue) {
        case .system:
            self
        case .light:
            self.preferredColorScheme(.light)
        case .dark:
            self.preferredColorScheme(.dark)
        }
    }
}
