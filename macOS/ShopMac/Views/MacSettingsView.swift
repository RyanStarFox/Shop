import SwiftUI
import ShopCore

struct MacSettingsView: View {
    @EnvironmentObject private var dataStore: DataStore
    @EnvironmentObject private var undoCoordinator: UndoCoordinator
    @EnvironmentObject private var webdavSync: WebDAVSyncService
    @EnvironmentObject private var syncCoordinator: SyncCoordinator

    @AppStorage("webdav_server") private var webdavServer = ""
    @AppStorage("webdav_username") private var webdavUsername = ""
    @AppStorage("webdav_path") private var webdavPath = ""
    @AppStorage("appearance_mode") private var appearanceMode = AppearancePreference.system.rawValue
    @State private var webdavPassword = ""
    @State private var webdavSyncTask: Task<Void, Never>?

    var body: some View {
        TabView {
            Form {
                Picker(ShopStrings.appearance, selection: $appearanceMode) {
                    Text(ShopStrings.appearanceSystem).tag(AppearancePreference.system.rawValue)
                    Text(ShopStrings.appearanceLight).tag(AppearancePreference.light.rawValue)
                    Text(ShopStrings.darkMode).tag(AppearancePreference.dark.rawValue)
                }
                .pickerStyle(.radioGroup)

                Picker(ShopStrings.dataRetention, selection: $dataStore.dataRetention) {
                    ForEach(DataRetentionPolicy.allCases, id: \.self) { policy in
                        Text(policy.localizedTitle).tag(policy)
                    }
                }

                Text(ShopStrings.dataRetentionFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .padding()
            .tabItem {
                Label(ShopStrings.appearance, systemImage: "paintpalette")
            }

            WebDAVSettingsTab(
                server: $webdavServer,
                folderPath: $webdavPath,
                username: $webdavUsername,
                password: $webdavPassword,
                isConfigured: webdavSync.isConfigured,
                isSyncing: syncCoordinator.status.isSyncing,
                lastSync: syncCoordinator.status.lastSuccess,
                error: syncCoordinator.status.failureMessage ?? webdavSync.error,
                onSync: saveCredentialsAndSync
            )
            .tabItem {
                Label(ShopStrings.sync, systemImage: "arrow.triangle.2.circlepath")
            }

            MacTagSettingsTab()
                .environmentObject(dataStore)
                .environmentObject(undoCoordinator)
                .tabItem {
                    Label(ShopStrings.tags, systemImage: "tag")
                }
        }
        .frame(width: 480, height: 460)
        .tint(ShopTheme.naturalGreen)
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
        .onDisappear {
            webdavSyncTask?.cancel()
            webdavPassword = ""
        }
    }

    private func saveCredentialsAndSync() {
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
}

// MARK: - WebDAV Settings Tab

private struct WebDAVSettingsTab: View {
    @Binding var server: String
    @Binding var folderPath: String
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
                TextField(ShopStrings.webdavFolderPath, text: $folderPath)
                    .textFieldStyle(.roundedBorder)
                Text(ShopStrings.webdavFolderPathHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(ShopStrings.webdavUsername, text: $username)
                    .textFieldStyle(.roundedBorder)
                SecureField(ShopStrings.webdavPassword, text: $password)
                    .textFieldStyle(.roundedBorder)
            } header: {
                Text(ShopStrings.webdavConfig)
            }

            Section {
                HStack {
                    Button(ShopStrings.syncNow, action: onSync)
                        .disabled(server.isEmpty || username.isEmpty || isSyncing)

                    if isSyncing {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Spacer()

                    if let error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    } else if let lastSync {
                        Text("\(ShopStrings.lastSync): \(lastSync.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if isConfigured {
                        Text(ShopStrings.webdavConfigured)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Tag Settings Tab

private struct MacTagSettingsTab: View {
    @EnvironmentObject private var dataStore: DataStore
    @EnvironmentObject private var undoCoordinator: UndoCoordinator

    @State private var newTagName = ""
    @State private var newTagColor = "#007AFF"
    @FocusState private var isNewTagFocused: Bool

    private let presetColors: [(String, Color)] = MacTagPalette.colors

    var body: some View {
        VStack(spacing: 0) {
            addTagBar
                .padding()

            Divider()

            if dataStore.tags.isEmpty {
                emptyTags
            } else {
                List {
                    ForEach(dataStore.tags) { tag in
                        MacTagEditRow(
                            tag: tag,
                            onDelete: {
                                dataStore.deleteTag(tag, presentUndo: undoCoordinator.present)
                            },
                            onRename: { newName in
                                dataStore.updateTag(tag, name: newName)
                            },
                            onColorChange: { newColor in
                                dataStore.updateTag(tag, colorHex: newColor)
                            }
                        )
                    }
                }
                .listStyle(.inset)
            }
        }
        .onAppear {
            isNewTagFocused = true
        }
    }

    private var addTagBar: some View {
        VStack(alignment: .leading, spacing: ShopTheme.spacingSM) {
            Text(ShopStrings.addTag)
                .font(.headline)

            HStack(spacing: ShopTheme.spacingSM) {
                TextField(ShopStrings.tagName, text: $newTagName)
                    .textFieldStyle(.roundedBorder)
                    .focused($isNewTagFocused)
                    .onSubmit(addTag)

                MacTagColorPicker(
                    selectedColor: $newTagColor,
                    colors: presetColors
                )

                Button(ShopStrings.addTag, action: addTag)
                    .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var emptyTags: some View {
        VStack(spacing: ShopTheme.spacingSM) {
            Image(systemName: "tag.slash")
                .font(.title)
                .foregroundStyle(.secondary)
            Text(ShopStrings.noTags)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func addTag() {
        let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        dataStore.addTag(name: name, colorHex: newTagColor)
        newTagName = ""
        newTagColor = "#007AFF"
    }
}

// MARK: - Tag Edit Row

private struct MacTagEditRow: View {
    let tag: Tag
    let onDelete: () -> Void
    let onRename: (String) -> Void
    let onColorChange: (String) -> Void

    @State private var isEditing = false
    @State private var editName: String

    private let presetColors: [(String, Color)] = MacTagPalette.colors

    init(
        tag: Tag,
        onDelete: @escaping () -> Void,
        onRename: @escaping (String) -> Void,
        onColorChange: @escaping (String) -> Void
    ) {
        self.tag = tag
        self.onDelete = onDelete
        self.onRename = onRename
        self.onColorChange = onColorChange
        _editName = State(initialValue: tag.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ShopTheme.spacingSM) {
            HStack(spacing: ShopTheme.spacingSM + 4) {
                Circle()
                    .fill(tag.displayColor)
                    .frame(width: 14, height: 14)

                if isEditing {
                    TextField(ShopStrings.tagName, text: $editName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(commitRename)
                } else {
                    Text(tag.name)
                        .font(.body.weight(.medium))
                }

                Spacer()

                Button {
                    if isEditing {
                        commitRename()
                    } else {
                        editName = tag.name
                        isEditing = true
                    }
                } label: {
                    Image(systemName: isEditing ? "checkmark.circle.fill" : "pencil.circle")
                        .foregroundStyle(isEditing ? ShopTheme.naturalGreen : .secondary)
                }
                .buttonStyle(.plain)
                .help(isEditing ? ShopStrings.saveItem : ShopStrings.editItem)

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash.circle")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help(ShopStrings.deleteItem)
            }

            if isEditing {
                MacTagColorPicker(
                    selectedColor: .init(
                        get: { tag.colorHex },
                        set: { onColorChange($0) }
                    ),
                    colors: presetColors,
                    dotSize: 22
                )
            }
        }
        .padding(.vertical, ShopTheme.spacingXS)
        .onChange(of: tag.name) { _, newName in
            editName = newName
        }
    }

    private func commitRename() {
        let trimmed = editName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onRename(trimmed)
        isEditing = false
    }
}

// MARK: - Shared Palette

private enum MacTagPalette {
    static let colors: [(String, Color)] = [
        ("#007AFF", .blue), ("#34C759", .green), ("#FF9500", .orange),
        ("#FF3B30", .red), ("#AF52DE", .purple), ("#FF2D55", .pink),
        ("#5856D6", .indigo), ("#00C7BE", .teal), ("#FFD60A", .yellow), ("#8E8E93", .gray)
    ]
}

private struct MacTagColorPicker: View {
    @Binding var selectedColor: String
    let colors: [(String, Color)]
    var dotSize: CGFloat = 20

    var body: some View {
        HStack(spacing: ShopTheme.spacingXS) {
            ForEach(colors.prefix(5), id: \.0) { hex, color in
                Button {
                    selectedColor = hex
                } label: {
                    Circle()
                        .fill(color)
                        .frame(width: dotSize, height: dotSize)
                        .overlay {
                            if selectedColor == hex {
                                Circle()
                                    .stroke(.white, lineWidth: 2)
                                    .frame(width: dotSize + 2, height: dotSize + 2)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
