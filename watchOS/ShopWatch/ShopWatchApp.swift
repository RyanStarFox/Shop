import SwiftUI
import WatchKit
import ShopCore

@main
struct ShopWatchApp: App {
    @StateObject private var dataStore = DataStore()
    @StateObject private var watchSync = WatchSyncService()
    @AppStorage("appearance_mode") private var appearanceMode = AppearancePreference.system.rawValue
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(dataStore)
                .environmentObject(watchSync)
                .tint(ShopTheme.brandColor)
                .preferredColorScheme(AppearancePreference(storageValue: appearanceMode).colorScheme)
                .onAppear {
                    watchSync.configure(with: dataStore)
                    watchSync.requestLatestSnapshot()
                    watchSync.sendLatestSnapshot()
                    dataStore.pruneExpiredData()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    watchSync.requestLatestSnapshot()
                    watchSync.sendLatestSnapshot()
                    dataStore.pruneExpiredData()
                }
        }
    }
}
