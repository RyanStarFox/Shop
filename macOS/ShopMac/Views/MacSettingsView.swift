import SwiftUI
import AppKit
import ShopCore

struct MacSettingsView: View {
    @Environment(\.shopAccent) private var shopAccent
    @EnvironmentObject private var dataStore: DataStore
    @EnvironmentObject private var undoCoordinator: UndoCoordinator
    @EnvironmentObject private var webdavSync: WebDAVSyncService
    @EnvironmentObject private var syncCoordinator: SyncCoordinator

    @AppStorage("webdav_server") private var webdavServer = ""
    @AppStorage("webdav_username") private var webdavUsername = ""
    @AppStorage("webdav_path") private var webdavPath = ""
    @AppStorage("appearance_mode") private var appearanceMode = AppearancePreference.system.rawValue
    @AppStorage(ThemeAccent.storageKey) private var themeHex = ThemeAccent.defaultHex
    @State private var webdavPassword = ""
    @State private var webdavSyncTask: Task<Void, Never>?
    @State private var pane = SettingsPane.appearance
    @Namespace private var tabGlass

    var body: some View {
        Group {
            switch pane {
            case .appearance:
                appearanceForm
            case .sync:
                WebDAVSettingsTab(
                    server: $webdavServer,
                    folderPath: $webdavPath,
                    username: $webdavUsername,
                    password: $webdavPassword,
                    isConfigured: webdavSync.isConfigured,
                    isSyncing: syncCoordinator.status.isSyncing,
                    lastSync: syncCoordinator.status.lastSuccess,
                    error: webdavSync.error ?? syncCoordinator.status.failureMessage,
                    resolvedFileURL: webdavSync.resolvedFileURL,
                    onSync: saveCredentialsAndSync
                )
            case .tags:
                MacTagSettingsTab()
                    .environmentObject(dataStore)
                    .environmentObject(undoCoordinator)
            }
        }
        .frame(width: 480, height: 520)
        .toolbar {
            settingsToolbar
        }
        .background(SettingsWindowTitle(title: pane.title))
        .tint(shopAccent)
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

    private var appearanceForm: some View {
        Form {
            Picker(ShopStrings.appearance, selection: $appearanceMode) {
                Text(ShopStrings.appearanceSystem).tag(AppearancePreference.system.rawValue)
                Text(ShopStrings.appearanceLight).tag(AppearancePreference.light.rawValue)
                Text(ShopStrings.darkMode).tag(AppearancePreference.dark.rawValue)
            }
            .pickerStyle(.radioGroup)

            themeColorSection

            Picker(ShopStrings.dataRetention, selection: $dataStore.dataRetention) {
                ForEach(DataRetentionPolicy.allCases, id: \.self) { policy in
                    Text(policy.localizedTitle).tag(policy)
                }
            }

            Text(ShopStrings.dataRetentionFooter)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                NotificationCenter.default.post(name: .shopShowOnboarding, object: nil)
            } label: {
                Label(ShopStrings.viewTutorial, systemImage: "book")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    @ToolbarContentBuilder
    private var settingsToolbar: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItemGroup(placement: .principal) {
                settingsTabs
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItemGroup(placement: .principal) {
                settingsTabs
            }
        }
    }

    @ViewBuilder
    private var settingsTabs: some View {
        if #available(macOS 26.0, *) {
            glassSettingsTabs
        } else {
            HStack(spacing: 4) {
                ForEach(SettingsPane.allCases) { item in
                    legacySettingsTab(item)
                }
            }
        }
    }

    @available(macOS 26.0, *)
    private var glassSettingsTabs: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(SettingsPane.allCases) { item in
                    glassSettingsTab(item)
                }
            }
        }
        .animation(.smooth(duration: 0.32), value: pane)
    }

    @available(macOS 26.0, *)
    private func glassSettingsTab(_ item: SettingsPane) -> some View {
        let selected = pane == item
        return settingsTabLabel(item, selected: selected)
            .glassEffect(
                selected ? .regular.interactive() : .identity,
                in: RoundedRectangle(cornerRadius: SettingsPane.cornerRadius, style: .continuous)
            )
            .glassEffectID(selected ? "settings-tab-selection" : item.id, in: tabGlass)
            .glassEffectTransition(.matchedGeometry)
    }

    private func legacySettingsTab(_ item: SettingsPane) -> some View {
        settingsTabLabel(item, selected: pane == item)
    }

    private func settingsTabLabel(_ item: SettingsPane, selected: Bool) -> some View {
        Button {
            pane = item
        } label: {
            VStack(spacing: 1) {
                Image(systemName: item.symbol)
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 16, weight: .medium))
                Text(item.title)
                    .font(.system(size: 10))
            }
            .foregroundStyle(selected ? shopAccent : Color.secondary)
            .frame(width: SettingsPane.side, height: SettingsPane.side)
            .contentShape(RoundedRectangle(cornerRadius: SettingsPane.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var customThemeColor: Binding<Color> {
        Binding(
            get: { ThemeAccent.color(hex: themeHex) },
            set: { newColor in
                guard let hex = newColor.shopHexString else { return }
                if ThemeAccent.isSystemBlue(themeHex),
                   let systemHex = Color.blue.shopHexString,
                   ThemeAccent.matches(hex, systemHex) {
                    return
                }
                themeHex = hex
            }
        )
    }

    private var themeColorSection: some View {
        VStack(alignment: .leading, spacing: ShopTheme.spacingSM) {
            Text(ShopStrings.themeColor)
            HStack(spacing: ShopTheme.spacingSM) {
                ForEach(ThemeAccent.presets) { preset in
                    let selected = ThemeAccent.matches(themeHex, preset.hex)
                    Button {
                        themeHex = preset.hex
                    } label: {
                        Circle()
                            .fill(ThemeAccent.color(hex: preset.hex))
                            .frame(width: 22, height: 22)
                            .padding(3)
                            .overlay {
                                Circle()
                                    .strokeBorder(selected ? Color.primary : Color.clear, lineWidth: 2)
                            }
                    }
                    .buttonStyle(.plain)
                    .help(ShopStrings.themePresetName(preset.id))
                    .accessibilityLabel(ShopStrings.themePresetName(preset.id))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            ColorPicker(ShopStrings.themeCustom, selection: customThemeColor, supportsOpacity: false)
            Button(ShopStrings.themeReset) {
                themeHex = ThemeAccent.defaultHex
            }
            .disabled(ThemeAccent.matches(themeHex, ThemeAccent.defaultHex))
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

private enum SettingsPane: String, CaseIterable, Identifiable {
    /// Selected glass plate matches the system tab: a rounded square, not a wide bar.
    static let side: CGFloat = 46
    static let cornerRadius: CGFloat = 12

    case appearance
    case sync
    case tags

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance: ShopStrings.appearance
        case .sync: ShopStrings.sync
        case .tags: ShopStrings.tags
        }
    }

    var symbol: String {
        switch self {
        case .appearance: "paintpalette"
        case .sync: "arrow.triangle.2.circlepath"
        case .tags: "tag"
        }
    }
}

private struct SettingsWindowTitle: NSViewRepresentable {
    var title: String

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            nsView.window?.title = title
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
    let resolvedFileURL: String?
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
                Button(ShopStrings.syncNow, action: onSync)
                    .disabled(server.isEmpty || username.isEmpty || isSyncing)

                if isSyncing {
                    ProgressView(ShopStrings.syncing)
                        .controlSize(.small)
                } else if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                } else if let lastSync {
                    Text("\(ShopStrings.lastSync): \(lastSync.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if isConfigured {
                    Text(ShopStrings.webdavConfigured)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let resolvedFileURL {
                    Text("\(ShopStrings.webdavTargetURLPrefix)\(resolvedFileURL)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
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
    @Environment(\.shopAccent) private var shopAccent
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
                        .foregroundStyle(isEditing ? shopAccent : .secondary)
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
// See MacTagEditorComponents.swift

