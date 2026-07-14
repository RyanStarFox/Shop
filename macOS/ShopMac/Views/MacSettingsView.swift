import SwiftUI
import ShopCore

struct MacSettingsView: View {
    @EnvironmentObject var dataStore: DataStore
    @EnvironmentObject var webdavSync: WebDAVSyncService

    @AppStorage("webdav_server") private var webdavServer = ""
    @AppStorage("webdav_username") private var webdavUsername = ""
    @State private var webdavPassword = ""
    @State private var webdavSyncTask: Task<Void, Never>?

    var body: some View {
        TabView {
            WebDAVSettingsTab(
                server: $webdavServer,
                username: $webdavUsername,
                password: $webdavPassword,
                isConfigured: webdavSync.isConfigured,
                isSyncing: webdavSync.isSyncing,
                lastSync: webdavSync.lastSyncDate,
                error: webdavSync.error,
                onSync: {
                    webdavSyncTask = Task {
                        do {
                            try webdavSync.saveCredentials(
                                serverURL: webdavServer,
                                username: webdavUsername,
                                password: webdavPassword
                            )
                            webdavPassword = ""
                            await webdavSync.syncNow()
                        } catch {
                            // The service exposes the localized error without revealing credentials.
                        }
                    }
                }
            )
            .tabItem {
                Label(ShopStrings.sync, systemImage: "arrow.triangle.2.circlepath")
            }

            TagSettingsTab()
                .environmentObject(dataStore)
                .tabItem {
                    Label(ShopStrings.tags, systemImage: "tag")
                }
        }
        .frame(width: 450, height: 400)
        .onAppear {
            webdavSync.migrateLegacyPasswordIfNeeded(
                serverURL: webdavServer,
                username: webdavUsername
            )
            webdavSync.restoreCredentials(
                serverURL: webdavServer,
                username: webdavUsername
            )
        }
        .onDisappear {
            webdavSyncTask?.cancel()
            webdavPassword = ""
        }
    }
}

// MARK: - WebDAV Settings Tab

struct WebDAVSettingsTab: View {
    @Binding var server: String
    @Binding var username: String
    @Binding var password: String
    let isConfigured: Bool
    let isSyncing: Bool
    let lastSync: Date?
    let error: String?
    let onSync: () -> Void

    var body: some View {
        Form {
            Section {
                TextField(ShopStrings.webdavServer, text: $server)
                    .textFieldStyle(.roundedBorder)
                TextField(ShopStrings.webdavUsername, text: $username)
                    .textFieldStyle(.roundedBorder)
                SecureField(ShopStrings.webdavPassword, text: $password)
                    .textFieldStyle(.roundedBorder)
            } header: {
                Text(ShopStrings.webdavConfig)
            }

            Section {
                HStack {
                    Button(ShopStrings.syncNow) {
                        onSync()
                    }
                    .disabled(server.isEmpty || username.isEmpty || isSyncing)

                    if isSyncing {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Spacer()

                    if let lastSync {
                        Text("\(ShopStrings.lastSync): \(lastSync.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if isConfigured {
                        Text(ShopStrings.webdavConfigured)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Tag Settings Tab

struct TagSettingsTab: View {
    @EnvironmentObject var dataStore: DataStore
    @State private var newTagName = ""
    @State private var newTagColor = "#007AFF"

    private let presetColors: [(String, Color)] = [
        ("#007AFF", .blue), ("#34C759", .green), ("#FF9500", .orange),
        ("#FF3B30", .red), ("#AF52DE", .purple), ("#FF2D55", .pink),
        ("#5856D6", .indigo), ("#00C7BE", .teal), ("#FFD60A", .yellow), ("#8E8E93", .gray)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Add new tag
            HStack(spacing: 8) {
                TextField(ShopStrings.tagName, text: $newTagName)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 4) {
                    ForEach(presetColors.prefix(5), id: \.0) { hex, color in
                        Button {
                            newTagColor = hex
                        } label: {
                            Circle()
                                .fill(color)
                                .frame(width: 20, height: 20)
                                .overlay {
                                    if newTagColor == hex {
                                        Circle()
                                            .stroke(.white, lineWidth: 2)
                                            .frame(width: 22, height: 22)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button(ShopStrings.addTag) {
                    let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    dataStore.addTag(name: name, colorHex: newTagColor)
                    newTagName = ""
                }
                .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()

            Divider()

            // Existing tags
            if dataStore.tags.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tag.slash")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text(ShopStrings.noTags)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(dataStore.tags) { tag in
                        HStack {
                            Circle()
                                .fill(tag.displayColor)
                                .frame(width: 12, height: 12)
                            Text(tag.name)
                            Spacer()
                            Button(role: .destructive) {
                                dataStore.deleteTag(tag)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}
