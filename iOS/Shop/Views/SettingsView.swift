import SwiftUI
import ShopCore

struct SettingsView: View {
    @EnvironmentObject var dataStore: DataStore
    @EnvironmentObject var wifiSync: WiFiSyncService
    @EnvironmentObject var webdavSync: WebDAVSyncService
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    @AppStorage("webdav_server") private var webdavServer = ""
    @AppStorage("webdav_username") private var webdavUsername = ""
    @AppStorage("appearance_mode") private var appearanceMode = "system"
    @State private var webdavPassword = ""
    @State private var showTagManagement = false
    @State private var webdavSyncTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassBackground()

                ScrollView {
                    VStack(spacing: 20) {
                        // Appearance
                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Label(ShopStrings.appearance, systemImage: "paintpalette")
                                    .font(.headline)

                                Picker(ShopStrings.appearance, selection: $appearanceMode) {
                                    Text("System").tag("system")
                                    Text("Light").tag("light")
                                    Text(ShopStrings.darkMode).tag("dark")
                                }
                                .pickerStyle(.segmented)
                            }
                        }
                        .padding(.horizontal)

                        // WiFi Sync Status
                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Label(ShopStrings.syncWifiStatus, systemImage: "wifi")
                                    .font(.headline)

                                HStack {
                                    Circle()
                                        .fill(wifiSync.isReachable ? Color.green : Color.secondary)
                                        .frame(width: 8, height: 8)
                                    Text(wifiSync.isReachable
                                        ? ShopStrings.syncAvailable
                                        : ShopStrings.syncNotAvailable
                                    )
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                }

                                if let lastSync = wifiSync.lastSyncDate {
                                    Text("\(ShopStrings.lastSync): \(lastSync.formatted(.relative(presentation: .named)))")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }

                                GlassButton(
                                    ShopStrings.syncNow,
                                    systemImage: "arrow.triangle.2.circlepath",
                                    isFullWidth: true
                                ) {
                                    wifiSync.pushData()
                                }
                                .disabled(!wifiSync.isReachable)
                                .opacity(wifiSync.isReachable ? 1 : 0.5)
                            }
                        }
                        .padding(.horizontal)

                        // WebDAV Configuration
                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Label(ShopStrings.webdavConfig, systemImage: "cloud")
                                    .font(.headline)

                                GlassTextField(
                                    placeholder: ShopStrings.webdavServer,
                                    text: $webdavServer,
                                    systemImage: "link"
                                )

                                GlassTextField(
                                    placeholder: ShopStrings.webdavUsername,
                                    text: $webdavUsername,
                                    systemImage: "person"
                                )

                                HStack(spacing: 12) {
                                    Image(systemName: "lock")
                                        .foregroundStyle(.secondary)
                                    SecureField(ShopStrings.webdavPassword, text: $webdavPassword)
                                        .textFieldStyle(.plain)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(.ultraThinMaterial)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .stroke(.white.opacity(0.2), lineWidth: 1)
                                        }
                                }

                                GlassButton(
                                    ShopStrings.syncNow,
                                    systemImage: "arrow.triangle.2.circlepath",
                                    isFullWidth: true
                                ) {
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
                                .disabled(
                                    webdavServer.isEmpty
                                        || webdavUsername.isEmpty
                                        || webdavSync.isSyncing
                                )

                                if webdavSync.isSyncing {
                                    ProgressView(ShopStrings.syncing)
                                        .font(.caption)
                                } else if let error = webdavSync.error {
                                    Text(error)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                } else if let lastSync = webdavSync.lastSyncDate {
                                    Text("\(ShopStrings.lastSync): \(lastSync.formatted(.relative(presentation: .named)))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal)

                        // Tag Management
                        GlassCard {
                            Button {
                                showTagManagement = true
                            } label: {
                                HStack {
                                    Label(ShopStrings.manageTags, systemImage: "tag")
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal)

                        // About
                        GlassCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Label(ShopStrings.about, systemImage: "info.circle")
                                    .font(.headline)

                                Text("Shop! v1.0.0")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text("A beautiful shopping list for all your devices")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle(ShopStrings.settings)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .sheet(isPresented: $showTagManagement) {
                TagManagementView()
                    .presentationCornerRadius(32)
            }
            .onDisappear {
                webdavSyncTask?.cancel()
                webdavPassword = ""
            }
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
        }
    }
}
