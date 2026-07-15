import SwiftUI
import ShopCore

struct MacContentView: View {
    @EnvironmentObject private var dataStore: DataStore
    @EnvironmentObject private var undoCoordinator: UndoCoordinator
    @EnvironmentObject private var webdavSync: WebDAVSyncService
    @EnvironmentObject private var syncCoordinator: SyncCoordinator

    @State private var selectedItemID: UUID?
    @State private var searchText = ""
    @State private var newItemName = ""
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @FocusState private var isSearchFocused: Bool
    @FocusState private var isAddFocused: Bool

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } content: {
            contentColumn
                .navigationSplitViewColumnWidth(min: 280, ideal: 320)
        } detail: {
            detailColumn
                .navigationSplitViewColumnWidth(min: 260, ideal: 300)
        }
        .navigationSplitViewStyle(.balanced)
        .tint(ShopTheme.naturalGreen)
        .background(VisualEffectView(material: .windowBackground, blendingMode: .behindWindow))
        .overlay(alignment: .bottom) {
            MacUndoBanner(undoCoordinator: undoCoordinator)
        }
        .onDeleteCommand(perform: deleteSelectedItem)
        .background {
            Group {
                Button(ShopStrings.addItem) { focusAddField() }
                    .keyboardShortcut("n", modifiers: .command)
                Button(ShopStrings.itemSearch) { isSearchFocused = true }
                    .keyboardShortcut("f", modifiers: .command)
                Button(ShopStrings.syncNow) { triggerSync() }
                    .keyboardShortcut("r", modifiers: .command)
            }
            .hidden()
        }
        .onChange(of: dataStore.items) { _, items in
            guard let selectedItemID else { return }
            if !items.contains(where: { $0.id == selectedItemID }) {
                self.selectedItemID = nil
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            quickAddBar
                .padding(ShopTheme.spacingSM + 4)

            Divider()

            List(selection: $dataStore.selectedFilter) {
                Section(ShopStrings.filter) {
                    ForEach(DataStore.FilterOption.allCases, id: \.self) { option in
                        Label(filterLabel(for: option), systemImage: iconForFilter(option))
                            .tag(option)
                    }
                }

                if !dataStore.tags.isEmpty {
                    Section(ShopStrings.tags) {
                        ForEach(dataStore.tags) { tag in
                            Button {
                                toggleTagFilter(tag.id)
                            } label: {
                                HStack(spacing: ShopTheme.spacingSM) {
                                    Circle()
                                        .fill(tag.displayColor)
                                        .frame(width: 10, height: 10)
                                    Text(tag.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if dataStore.selectedTags.contains(tag.id) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(ShopTheme.naturalGreen)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(
                                dataStore.selectedTags.contains(tag.id) ? .isSelected : []
                            )
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            syncStatusBar
                .padding(ShopTheme.spacingSM + 4)
        }
        .navigationTitle(ShopStrings.appName)
    }

    private var quickAddBar: some View {
        HStack(spacing: ShopTheme.spacingSM) {
            TextField(ShopStrings.addItem, text: $newItemName)
                .textFieldStyle(.roundedBorder)
                .focused($isAddFocused)
                .onSubmit(addItem)

            Button(action: addItem) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(ShopTheme.naturalGreen)
            }
            .buttonStyle(.plain)
            .disabled(newItemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help(ShopStrings.addItem)
        }
    }

    // MARK: - Content Column

    private var contentColumn: some View {
        VStack(spacing: 0) {
            if hasAnyItems {
                searchBar
                    .padding(ShopTheme.spacingSM + 4)
            }

            if filteredItems.isEmpty {
                emptyList
            } else {
                MacItemListView(
                    filteredItems: filteredItems,
                    searchIsActive: !searchText.isEmpty,
                    selectedItemID: $selectedItemID,
                    onToggleCompletion: toggleCompletion,
                    onDeleteItem: deleteItem
                )
            }

            statusBar
        }
        .navigationTitle(listTitle)
    }

    private var searchBar: some View {
        HStack(spacing: ShopTheme.spacingSM) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(ShopStrings.itemSearch, text: $searchText)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, ShopTheme.spacingSM + 4)
        .padding(.vertical, ShopTheme.spacingSM)
        .macGlassSurface(in: RoundedRectangle(cornerRadius: ShopTheme.rowCornerRadius, style: .continuous))
    }

    private var emptyList: some View {
        VStack(spacing: ShopTheme.spacingMD) {
            Image(systemName: "cart")
                .font(.system(size: 52, weight: .medium))
                .foregroundStyle(.secondary)

            Text(ShopStrings.emptyList)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: ShopTheme.spacingXS) {
                Text(String(localized: "mac.empty_add_shortcut"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text(String(localized: "mac.empty_search_shortcut"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(ShopTheme.spacingMD)
    }

    private var statusBar: some View {
        HStack {
            Text(ShopStrings.pendingCount(dataStore.activeItems.count))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if syncCoordinator.status.isSyncing {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, ShopTheme.spacingMD)
        .padding(.vertical, ShopTheme.spacingSM)
        .background(.ultraThinMaterial)
    }

    // MARK: - Detail Column

    @ViewBuilder
    private var detailColumn: some View {
        if let selectedItemID, let item = item(for: selectedItemID) {
            MacItemDetailView(itemID: selectedItemID)
                .id(item.id)
        } else {
            detailPlaceholder
        }
    }

    private var detailPlaceholder: some View {
        VStack(spacing: ShopTheme.spacingMD) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(.secondary)
            Text(String(localized: "mac.detail_placeholder"))
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(ShopTheme.spacingMD)
    }

    // MARK: - Sync Status

    private var syncStatusBar: some View {
        VStack(alignment: .leading, spacing: ShopTheme.spacingXS) {
            HStack(spacing: ShopTheme.spacingXS + 2) {
                Circle()
                    .fill(webdavSync.isConfigured ? ShopTheme.naturalGreen : Color.secondary)
                    .frame(width: 8, height: 8)

                Text(
                    webdavSync.isConfigured
                        ? ShopStrings.webdavConfigured
                        : ShopStrings.webdavNotConfigured
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                if webdavSync.isConfigured {
                    Button {
                        triggerSync()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .disabled(syncCoordinator.status.isSyncing)
                    .help(ShopStrings.syncNow)
                }
            }

            if syncCoordinator.status.isSyncing {
                Text(ShopStrings.syncing)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else if let error = syncCoordinator.status.failureMessage ?? webdavSync.error {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            } else if let lastSync = syncCoordinator.status.lastSuccess {
                Text("\(ShopStrings.lastSync): \(lastSync.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Actions

    private var hasAnyItems: Bool {
        !dataStore.items.isEmpty
    }

    private var filteredItems: [ShoppingItem] {
        let filtered = dataStore.filteredItems
        guard !searchText.isEmpty else { return filtered }
        return filtered.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var listTitle: String {
        switch dataStore.selectedFilter {
        case .all: ShopStrings.filterAll
        case .active: ShopStrings.filterActive
        case .completed: ShopStrings.filterCompleted
        case .today: ShopStrings.filterToday
        case .week: ShopStrings.filterWeek
        case .month: ShopStrings.filterMonth
        }
    }

    private func item(for id: UUID) -> ShoppingItem? {
        dataStore.items.first { $0.id == id }
    }

    private func focusAddField() {
        isAddFocused = true
    }

    private func addItem() {
        let name = newItemName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            focusAddField()
            return
        }
        dataStore.addItem(name: name)
        newItemName = ""
    }

    private func toggleTagFilter(_ id: UUID) {
        if dataStore.selectedTags.contains(id) {
            dataStore.selectedTags.remove(id)
        } else {
            dataStore.selectedTags.insert(id)
        }
    }

    private func toggleCompletion(_ item: ShoppingItem) {
        dataStore.setCompleted(
            item,
            completed: !item.isCompleted,
            presentUndo: undoCoordinator.present
        )
    }

    private func deleteItem(_ item: ShoppingItem) {
        if selectedItemID == item.id {
            selectedItemID = nil
        }
        dataStore.deleteItem(item, presentUndo: undoCoordinator.present)
    }

    private func deleteSelectedItem() {
        guard let selectedItemID, let item = item(for: selectedItemID) else { return }
        deleteItem(item)
    }

    private func triggerSync() {
        guard webdavSync.isConfigured, !syncCoordinator.status.isSyncing else { return }
        Task { await syncCoordinator.syncNow() }
    }

    private func filterLabel(for option: DataStore.FilterOption) -> String {
        switch option {
        case .all: ShopStrings.filterAll
        case .active: ShopStrings.filterActive
        case .completed: ShopStrings.filterCompleted
        case .today: ShopStrings.filterToday
        case .week: ShopStrings.filterWeek
        case .month: ShopStrings.filterMonth
        }
    }

    private func iconForFilter(_ option: DataStore.FilterOption) -> String {
        switch option {
        case .all: "list.bullet"
        case .active: "circle"
        case .completed: "checkmark.circle"
        case .today: "calendar"
        case .week: "calendar.badge.clock"
        case .month: "calendar"
        }
    }
}

// MARK: - Item List

private struct MacItemListView: View {
    let filteredItems: [ShoppingItem]
    let searchIsActive: Bool
    @Binding var selectedItemID: UUID?
    let onToggleCompletion: (ShoppingItem) -> Void
    let onDeleteItem: (ShoppingItem) -> Void

    @EnvironmentObject private var dataStore: DataStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var sections: ItemListSections {
        ItemListSections.derive(from: filteredItems)
    }

    private var canReorder: Bool {
        ItemListReorderPolicy.canReorder(
            filter: dataStore.selectedFilter,
            selectedTags: dataStore.selectedTags,
            dateRange: dataStore.dateRange,
            searchIsActive: searchIsActive
        )
    }

    private var itemLookup: [UUID: ShoppingItem] {
        Dictionary(uniqueKeysWithValues: filteredItems.map { ($0.id, $0) })
    }

    var body: some View {
        List(selection: $selectedItemID) {
            if !sections.activeIDs.isEmpty {
                Section {
                    activeRows
                }
            }

            if sections.showsArchiveSection {
                Section {
                    ForEach(sections.archivedIDs, id: \.self) { itemID in
                        if let item = itemLookup[itemID] {
                            row(for: item)
                                .tag(itemID)
                        }
                    }
                } header: {
                    Text(ShopStrings.archiveSection)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .animation(reduceMotion ? nil : .default, value: sections.displayRows)
    }

    @ViewBuilder
    private var activeRows: some View {
        let rows = ForEach(sections.activeIDs, id: \.self) { itemID in
            if let item = itemLookup[itemID] {
                row(for: item)
                    .tag(itemID)
            }
        }
        if canReorder {
            rows.onMove(perform: moveActiveItems)
        } else {
            rows
        }
    }

    private func row(for item: ShoppingItem) -> some View {
        MacItemRow(
            item: item,
            isSelected: selectedItemID == item.id,
            onToggleCompletion: { onToggleCompletion(item) }
        )
        .contextMenu {
            Button(role: .destructive) {
                onDeleteItem(item)
            } label: {
                Label(ShopStrings.deleteItem, systemImage: "trash")
            }
        }
    }

    private func moveActiveItems(from source: IndexSet, to destination: Int) {
        dataStore.moveItems(from: source, to: destination)
    }
}

// MARK: - Item Row

private struct MacItemRow: View {
    let item: ShoppingItem
    let isSelected: Bool
    let onToggleCompletion: () -> Void

    var body: some View {
        HStack(spacing: ShopTheme.spacingSM + 4) {
            Button(action: onToggleCompletion) {
                MacCompletionControl(isCompleted: item.isCompleted)
            }
            .buttonStyle(.plain)
            .help(item.isCompleted ? ShopStrings.markIncomplete : ShopStrings.markComplete)

            VStack(alignment: .leading, spacing: ShopTheme.spacingXS) {
                Text(item.name)
                    .font(.body)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                    .strikethrough(item.isCompleted, color: .secondary)
                    .lineLimit(2)

                if !item.tags.isEmpty {
                    MacTagRow(tags: item.tags)
                }
            }

            Spacer(minLength: 0)

            if item.isCompleted, let completedAt = item.completedAt {
                Text(completedAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, ShopTheme.spacingXS)
        .contentShape(Rectangle())
        .listRowBackground(
            isSelected
                ? ShopTheme.naturalGreen.opacity(0.12)
                : Color.clear
        )
    }
}

private struct MacCompletionControl: View {
    let isCompleted: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    isCompleted ? ShopTheme.naturalGreen : Color.secondary.opacity(0.35),
                    lineWidth: 2
                )
                .frame(width: 20, height: 20)

            if isCompleted {
                Circle()
                    .fill(ShopTheme.naturalGreen)
                    .frame(width: 20, height: 20)
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }
}

private struct MacTagRow: View {
    let tags: [Tag]

    var body: some View {
        HStack(spacing: ShopTheme.spacingSM) {
            ForEach(tags, id: \.id) { tag in
                HStack(spacing: ShopTheme.spacingXS) {
                    Circle()
                        .fill(tag.displayColor)
                        .frame(width: 6, height: 6)
                    Text(tag.name)
                        .font(.caption)
                        .foregroundStyle(tag.displayColor)
                        .lineLimit(1)
                }
            }
        }
    }
}

// MARK: - Detail Editor

private struct MacItemDetailView: View {
    let itemID: UUID

    @EnvironmentObject private var dataStore: DataStore

    @State private var itemName = ""
    @State private var selectedTags: Set<UUID> = []
    @FocusState private var isNameFocused: Bool

    private var item: ShoppingItem? {
        dataStore.items.first { $0.id == itemID }
    }

    var body: some View {
        Group {
            if let item {
                Form {
                    Section {
                        TextField(ShopStrings.itemName, text: $itemName)
                            .focused($isNameFocused)
                            .onSubmit { save(item) }
                    }

                    if !dataStore.tags.isEmpty {
                        Section(ShopStrings.tags) {
                            ForEach(dataStore.tags) { tag in
                                Toggle(isOn: tagBinding(tag.id)) {
                                    HStack(spacing: ShopTheme.spacingSM) {
                                        Circle()
                                            .fill(tag.displayColor)
                                            .frame(width: 10, height: 10)
                                        Text(tag.name)
                                    }
                                }
                                .toggleStyle(.checkbox)
                            }
                        }
                    }

                    Section {
                        if item.isCompleted, let completedAt = item.completedAt {
                            LabeledContent(ShopStrings.filterCompleted) {
                                Text(completedAt.formatted(date: .abbreviated, time: .shortened))
                            }
                        }
                        LabeledContent(ShopStrings.addedAt) {
                            Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                }
                .formStyle(.grouped)
                .onAppear { syncFromItem(item) }
                .onChange(of: item.updatedAt) { _, _ in
                    syncFromItemIfNeeded(item)
                }
                .onChange(of: itemName) { _, _ in
                    save(item)
                }
                .onChange(of: selectedTags) { _, _ in
                    save(item)
                }
            } else {
                ContentUnavailableView(
                    ShopStrings.editItem,
                    systemImage: "exclamationmark.triangle",
                    description: Text(String(localized: "mac.detail_missing_item"))
                )
            }
        }
        .navigationTitle(ShopStrings.editItem)
    }

    private func tagBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedTags.contains(id) },
            set: { isOn in
                if isOn {
                    selectedTags.insert(id)
                } else {
                    selectedTags.remove(id)
                }
            }
        )
    }

    private func syncFromItem(_ item: ShoppingItem) {
        itemName = item.name
        selectedTags = Set(item.tags.map(\.id))
    }

    private func syncFromItemIfNeeded(_ item: ShoppingItem) {
        let storeTags = Set(item.tags.map(\.id))
        let trimmed = itemName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == item.name, selectedTags == storeTags {
            return
        }
        syncFromItem(item)
    }

    private func save(_ item: ShoppingItem) {
        let trimmed = itemName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let tags = dataStore.tags.filter { selectedTags.contains($0.id) }
        let originalTags = Set(item.tags.map(\.id))
        guard trimmed != item.name || selectedTags != originalTags else { return }
        dataStore.updateItem(item, name: trimmed, tags: tags)
    }
}

// MARK: - Undo Banner

struct MacUndoBanner: View {
    @ObservedObject var undoCoordinator: UndoCoordinator
    @State private var undoError: String?

    var body: some View {
        if let action = undoCoordinator.currentAction {
            HStack(spacing: ShopTheme.spacingSM) {
                Text(action.message)
                    .font(.subheadline)
                    .lineLimit(2)

                Spacer(minLength: ShopTheme.spacingSM)

                Button(ShopStrings.undo) {
                    performUndo()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ShopTheme.naturalGreen)
            }
            .padding(.horizontal, ShopTheme.spacingMD)
            .padding(.vertical, ShopTheme.spacingSM)
            .macGlassSurface(in: RoundedRectangle(cornerRadius: ShopTheme.rowCornerRadius, style: .continuous))
            .padding(.horizontal, ShopTheme.spacingMD)
            .padding(.bottom, ShopTheme.spacingSM)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .alert(ShopStrings.undo, isPresented: Binding(
                get: { undoError != nil },
                set: { if !$0 { undoError = nil } }
            )) {
                Button(ShopStrings.dismiss, role: .cancel) {}
            } message: {
                Text(undoError ?? "")
            }
        }
    }

    private func performUndo() {
        do {
            try undoCoordinator.undo()
        } catch {
            undoError = error.localizedDescription
        }
    }
}

// MARK: - Glass + Visual Effect

private extension View {
    @ViewBuilder
    func macGlassSurface<S: Shape>(in shape: S) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay {
                    shape.stroke(.white.opacity(0.12), lineWidth: 0.5)
                }
        }
    }
}

#if os(macOS)
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
#endif
