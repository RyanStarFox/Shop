import SwiftUI
import ShopCore

struct SettingsView: View {
    @EnvironmentObject var dataStore: DataStore
    @EnvironmentObject var watchSync: WatchSyncService
    @EnvironmentObject var webdavSync: WebDAVSyncService
    @EnvironmentObject var syncCoordinator: SyncCoordinator
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    @AppStorage("webdav_server") private var webdavServer = ""
    @AppStorage("webdav_username") private var webdavUsername = ""
    @AppStorage("webdav_path") private var webdavPath = ""
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
                                    Text(ShopStrings.appearanceSystem).tag(AppearancePreference.system.rawValue)
                                    Text(ShopStrings.appearanceLight).tag(AppearancePreference.light.rawValue)
                                    Text(ShopStrings.darkMode).tag(AppearancePreference.dark.rawValue)
                                }
                                .pickerStyle(.segmented)
                            }
                        }
                        .padding(.horizontal)

                        // Watch Sync Status
                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Label(ShopStrings.syncWatchStatus, systemImage: "applewatch")
                                    .font(.headline)

                                HStack {
                                    Circle()
                                        .fill(watchSync.isReachable ? Color.green : Color.secondary)
                                        .frame(width: 8, height: 8)
                                    Text(watchSync.isReachable
                                        ? ShopStrings.syncAvailable
                                        : ShopStrings.syncNotAvailable
                                    )
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                }

                                if let lastSync = watchSync.lastSyncDate {
                                    Text("\(ShopStrings.lastSync): \(lastSync.formatted(.relative(presentation: .named)))")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }

                                GlassButton(
                                    ShopStrings.syncNow,
                                    systemImage: "arrow.triangle.2.circlepath",
                                    isFullWidth: true
                                ) {
                                    watchSync.sendLatestSnapshot()
                                }
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
                                    placeholder: ShopStrings.webdavFolderPath,
                                    text: $webdavPath,
                                    systemImage: "folder"
                                )

                                Text(ShopStrings.webdavFolderPathHint)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

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
                                                password: webdavPassword,
                                                folderPath: webdavPath
                                            )
                                            webdavPassword = ""
                                            await syncCoordinator.syncNow()
                                        } catch {
                                            // The service exposes the localized error without revealing credentials.
                                        }
                                    }
                                }
                                .disabled(
                                    webdavServer.isEmpty
                                        || webdavUsername.isEmpty
                                        || syncCoordinator.status.isSyncing
                                )

                                if syncCoordinator.status.isSyncing {
                                    ProgressView(ShopStrings.syncing)
                                        .font(.caption)
                                } else if let error = webdavSync.error ?? syncCoordinator.status.failureMessage {
                                    Text(error)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .textSelection(.enabled)
                                } else if let lastSync = syncCoordinator.status.lastSuccess {
                                    Text("\(ShopStrings.lastSync): \(lastSync.formatted(.relative(presentation: .named)))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                if let resolved = webdavSync.resolvedFileURL {
                                    Text("\(ShopStrings.webdavTargetURLPrefix)\(resolved)")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .textSelection(.enabled)
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

                        // Data retention
                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Label(ShopStrings.dataRetention, systemImage: "internaldrive")
                                    .font(.headline)

                                Picker(ShopStrings.dataRetention, selection: $dataStore.dataRetention) {
                                    ForEach(DataRetentionPolicy.allCases, id: \.self) { policy in
                                        Text(policy.localizedTitle).tag(policy)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Text(ShopStrings.dataRetentionFooter)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal)

                        // About
                        GlassCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Label(ShopStrings.about, systemImage: "info.circle")
                                    .font(.headline)

                                Text(ShopStrings.appVersion)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(ShopStrings.appTagline)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)

                                Link(destination: ShopLinks.githubRepository) {
                                    HStack(spacing: ShopTheme.spacingXS) {
                                        Image(systemName: "link")
                                            .font(.caption)
                                        Text(ShopStrings.githubRepository)
                                            .font(.subheadline)
                                        Spacer(minLength: 0)
                                        Image(systemName: "arrow.up.right")
                                            .font(.caption2)
                                    }
                                    .foregroundStyle(ShopTheme.brandRed)
                                }
                                .accessibilityLabel(ShopStrings.githubRepository)
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
                    .preferredColorScheme(
                        AppearancePreference(storageValue: appearanceMode).colorScheme
                    )
            }
            .onDisappear {
                webdavSyncTask?.cancel()
                webdavPassword = ""
            }
            .onAppear {
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
            }
        }
        .preferredColorScheme(AppearancePreference(storageValue: appearanceMode).colorScheme)
    }
}
