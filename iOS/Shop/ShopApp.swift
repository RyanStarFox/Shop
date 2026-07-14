import SwiftUI
import SwiftData
import ShopCore

@main
struct ShopApp: App {
    @StateObject private var dataStore = DataStore()
    @StateObject private var wifiSync = WiFiSyncService()
    @StateObject private var webdavSync = WebDAVSyncService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dataStore)
                .environmentObject(wifiSync)
                .environmentObject(webdavSync)
                .tint(.accentColor)
                .onAppear {
                    wifiSync.configure(with: dataStore)
                    webdavSync.configure(with: dataStore)
                }
        }
        .modelContainer(dataStore.modelContainer)
    }
}
