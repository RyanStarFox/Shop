import SwiftUI
import WatchKit
import ShopCore

@main
struct ShopWatchApp: App {
    @StateObject private var dataStore = DataStore()
    @StateObject private var watchSync = WatchSyncService()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(dataStore)
                .environmentObject(watchSync)
                .onAppear {
                    watchSync.configure(with: dataStore)
                    watchSync.requestLatestSnapshot()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    watchSync.requestLatestSnapshot()
                    watchSync.sendLatestSnapshot()
                }
        }
    }
}
