import SwiftUI
import ShopCore

@main
struct ShopMacApp: App {
    @StateObject private var dataStore = DataStore()
    @StateObject private var webdavSync = WebDAVSyncService()

    @AppStorage("webdav_server") private var webdavServer = ""
    @AppStorage("webdav_username") private var webdavUsername = ""

    var body: some Scene {
        WindowGroup {
            MacContentView()
                .environmentObject(dataStore)
                .environmentObject(webdavSync)
                .frame(minWidth: 400, idealWidth: 480, minHeight: 500, idealHeight: 700)
                .onAppear {
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
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        Settings {
            MacSettingsView()
                .environmentObject(dataStore)
                .environmentObject(webdavSync)
        }
    }
}
