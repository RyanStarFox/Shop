import SwiftUI
import SwiftData
import ShopCore

@main
struct ShopApp: App {
    @StateObject private var dataStore = DataStore()
    @StateObject private var wifiSync = WiFiSyncService()
    @StateObject private var webdavSync = WebDAVSyncService()
    @AppStorage("webdav_server") private var webdavServer = ""
    @AppStorage("webdav_username") private var webdavUsername = ""

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
    }
}
