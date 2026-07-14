import SwiftUI
import ShopCore

@main
struct ShopMacApp: App {
    @StateObject private var dataStore = DataStore()
    @StateObject private var webdavSync = WebDAVSyncService()

    @AppStorage("webdav_server") private var webdavServer = ""
    @AppStorage("webdav_username") private var webdavUsername = ""
    @AppStorage("webdav_password") private var webdavPassword = ""

    var body: some Scene {
        WindowGroup {
            MacContentView()
                .environmentObject(dataStore)
                .environmentObject(webdavSync)
                .frame(minWidth: 400, idealWidth: 480, minHeight: 500, idealHeight: 700)
                .onAppear {
                    webdavSync.configure(with: dataStore)
                    if !webdavServer.isEmpty {
                        webdavSync.configure(
                            serverURL: webdavServer,
                            username: webdavUsername,
                            password: webdavPassword
                        )
                    }
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
