import SwiftUI
import WatchKit
import ShopCore

@main
struct ShopWatchApp: App {
    @StateObject private var dataStore = DataStore()
    @StateObject private var wifiSync = WiFiSyncService()

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(dataStore)
                .environmentObject(wifiSync)
                .onAppear {
                    wifiSync.configure(with: dataStore)
                }
        }
    }
}
