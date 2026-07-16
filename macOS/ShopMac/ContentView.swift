import SwiftUI
import AppKit
import ShopCore

struct MacContentView: View {
    @EnvironmentObject private var dataStore: DataStore
    @EnvironmentObject private var undoCoordinator: UndoCoordinator
    @EnvironmentObject private var webdavSync: WebDAVSyncService
    @EnvironmentObject private var syncCoordinator: SyncCoordinator

    @State private var selectedItemIDs: Set<UUID> = []
    @State private var selectionAnchorID: UUID?
    @State private var showBatchDeleteConfirm = false
    @State private var searchText = ""
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var isDrafting = false
    @State private var draftName = ""
    @State private var draftSelectedTags: Set<UUID> = []
    @State private var draftCreatedAt = Date()
    @State private var isDetailTextFocused = false
    @State private var syncSpin = 0.0
    @State private var completionHapticToken = 0
    @State private var restoreHapticToken = 0
    @State private var refreshHapticToken = 0
    @FocusState private var isSearchFocused: Bool

    private var isMultiSelecting: Bool { selectedItemIDs.count > 1 }

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
        .tint(ShopTheme.brandColor)
        .background(VisualEffectView(material: .windowBackground, blendingMode: .behindWindow))
        .sensoryFeedback(.impact(weight: .heavy, intensity: 1.0), trigger: completionHapticToken)
        .sensoryFeedback(.impact(weight: .medium, intensity: 1.0), trigger: restoreHapticToken)
        .sensoryFeedback(.impact(weight: .heavy, intensity: 1.0), trigger: refreshHapticToken)
        .onDeleteCommand(perform: deleteSelectedItem)
        .alert(ShopStrings.selectionDeleteConfirmTitle, isPresented: $showBatchDeleteConfirm) {
            Button(ShopStrings.deleteItem, role: .destructive) {
                dataStore.deleteItems(Array(selectedItemIDs), presentUndo: undoCoordinator.present)
                selectedItemIDs = []
                selectionAnchorID = nil
            }
            Button(ShopStrings.dismiss, role: .cancel) {}
        } message: {
            Text(ShopStrings.selectionDeleteConfirmMessage(selectedItemIDs.count))
        }
        .background {
            Group {
                Button(ShopStrings.addItem) { beginDraft() }
                    .keyboardShortcut("n", modifiers: .command)
                Button(ShopStrings.undo) { performUndo() }
                    .keyboardShortcut("z", modifiers: .command)
                Button(ShopStrings.itemSearch) { isSearchFocused = true }
                    .keyboardShortcut("f", modifiers: .command)
                Button(ShopStrings.syncNow) { triggerSync() }
                    .keyboardShortcut("r", modifiers: .command)
            }
            .hidden()
        }
        .onChange(of: dataStore.items.map(\.id)) { _, _ in
            pruneSelection()
        }
        .onChange(of: filteredItems.map(\.id)) { _, _ in
            pruneSelection()
        }
        .onKeyPress(.space) {
            handleCompletionKeyPress()
        }
        .onKeyPress(.return) {
            handleCompletionKeyPress()
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $dataStore.selectedFilter) {
                Section {
                    Button(action: beginDraft) {
                        Label(ShopStrings.addItem, systemImage: "plus.circle")
                            .foregroundStyle(ShopTheme.brandColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .help(ShopStrings.addItem)
                    .accessibilityLabel(ShopStrings.addItem)
                }

                Section(ShopStrings.filter) {
                    ForEach(DataStore.FilterOption.allCases, id: \.self) { option in
                        Label(filterLabel(for: option), systemImage: iconForFilter(option))
                            .tag(option)
                    }
                }

                if !dataStore.tags.isEmpty {
                    Section(ShopStrings.tags) {
                        Button {
                            selectAllTagsFilter()
                        } label: {
                            HStack(spacing: ShopTheme.spacingSM) {
                                Circle()
                                    .fill(Color.black)
                                    .frame(width: 10, height: 10)
                                    .overlay {
                                        Circle()
                                            .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 0.5)
                                    }
                                Text(ShopStrings.allTags)
                                    .foregroundStyle(.primary)
                                Spacer(minLength: 0)
                                if dataStore.selectedTags.isEmpty {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(ShopTheme.brandColor)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(
                            dataStore.selectedTags.isEmpty ? .isSelected : []
                        )
                        .accessibilityLabel(ShopStrings.allTags)

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
                                    Spacer(minLength: 0)
                                    if dataStore.selectedTags.contains(tag.id) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(ShopTheme.brandColor)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(
                                dataStore.selectedTags.contains(tag.id) ? .isSelected : []
                            )
                            .accessibilityLabel(tag.name)
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

    // MARK: - Content Column

    private var contentColumn: some View {
        VStack(spacing: 0) {
            if hasAnyItems || isDrafting {
                searchBar
                    .padding(ShopTheme.spacingSM + 4)
            }

            if filteredItems.isEmpty && !isDrafting {
                GeometryReader { proxy in
                    ScrollView {
                        emptyList
                            .frame(maxHeight: .infinity)
                            .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                    }
                    .macPullToRefresh {
                        await performManualSync()
                    }
                }
            } else {
                MacItemListView(
                    filteredItems: filteredItems,
                    searchIsActive: !searchText.isEmpty,
                    selectedItemIDs: selectedItemIDs,
                    isDrafting: isDrafting,
                    onSelect: handleItemClick,
                    onSelectDraft: selectDraftRow,
                    onToggleCompletion: toggleCompletion,
                    onDeleteItem: deleteItem,
                    onRefresh: {
                        await performManualSync()
                    }
                )
            }
        }
        .navigationTitle(listTitle)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    performUndo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(undoCoordinator.currentAction == nil)
                .help(ShopStrings.undo)
                .accessibilityLabel(ShopStrings.undo)
                .accessibilityValue(undoCoordinator.currentAction?.message ?? "")

                Menu {
                    Section(ShopStrings.sort) {
                        ForEach(DataStore.SortOption.allCases, id: \.self) { option in
                            Button {
                                dataStore.sortOption = option
                            } label: {
                                if dataStore.sortOption == option {
                                    Label(option.macTitle, systemImage: "checkmark")
                                } else {
                                    Text(option.macTitle)
                                }
                            }
                        }
                    }
                    Section(ShopStrings.group) {
                        ForEach(DataStore.GroupOption.allCases, id: \.self) { option in
                            Button {
                                dataStore.groupOption = option
                            } label: {
                                if dataStore.groupOption == option {
                                    Label(option.macTitle, systemImage: "checkmark")
                                } else {
                                    Text(option.macTitle)
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down.circle")
                }
                .help("\(ShopStrings.sort) / \(ShopStrings.group)")
            }
        }
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

    // MARK: - Detail Column

    @ViewBuilder
    private var detailColumn: some View {
        if isDrafting {
            MacDraftDetailView(
                draftName: $draftName,
                draftSelectedTags: $draftSelectedTags,
                draftCreatedAt: $draftCreatedAt,
                isTextFocused: $isDetailTextFocused,
                onSave: commitDraft,
                onDiscard: discardDraft
            )
        } else if selectedItemIDs.count > 1 {
            MacBatchDetailView(
                selectedItemIDs: selectedItemIDs,
                onComplete: {
                    dataStore.setCompleted(
                        Array(selectedItemIDs),
                        completed: true,
                        presentUndo: undoCoordinator.present
                    )
                    completionHapticToken &+= 1
                    ShopHaptics.itemCompleted()
                },
                onRestore: {
                    dataStore.setCompleted(
                        Array(selectedItemIDs),
                        completed: false,
                        presentUndo: undoCoordinator.present
                    )
                    restoreHapticToken &+= 1
                    ShopHaptics.itemRestored()
                },
                onDelete: { showBatchDeleteConfirm = true }
            )
        } else if let selectedItemID = selectedItemIDs.first, item(for: selectedItemID) != nil {
            MacItemDetailView(
                itemID: selectedItemID,
                isTextFocused: $isDetailTextFocused
            )
            .id(selectedItemID)
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
                    .fill(webdavSync.isConfigured ? ShopTheme.brandColor : Color.secondary)
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
                            .rotationEffect(.degrees(syncSpin))
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
        .onAppear {
            if syncCoordinator.status.isSyncing { startSyncSpin() }
        }
        .onChange(of: syncCoordinator.status.isSyncing) { _, isSyncing in
            if isSyncing {
                startSyncSpin()
            } else {
                withAnimation(.easeOut(duration: 0.25)) { syncSpin = 0 }
            }
        }
    }

    private func startSyncSpin() {
        syncSpin = 0
        withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
            syncSpin = 360
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

    private func beginDraft() {
        isDrafting = true
        draftName = ""
        draftSelectedTags = []
        draftCreatedAt = Date()
        selectedItemIDs = []
        selectionAnchorID = nil
        isDetailTextFocused = true
    }

    private func discardDraft() {
        isDrafting = false
        draftName = ""
        draftSelectedTags = []
        draftCreatedAt = Date()
        isDetailTextFocused = false
    }

    private func commitDraft() {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let tags = dataStore.tags.filter { draftSelectedTags.contains($0.id) }
        let beforeIDs = Set(dataStore.items.map(\.id))
        dataStore.addItem(name: name, tags: tags, createdAt: draftCreatedAt)
        discardDraft()
        if let created = dataStore.items.first(where: { !beforeIDs.contains($0.id) && $0.name == name }) {
            selectedItemIDs = [created.id]
            selectionAnchorID = created.id
        } else if let fallback = dataStore.items.first(where: { $0.name == name }) {
            selectedItemIDs = [fallback.id]
            selectionAnchorID = fallback.id
        }
    }

    private func selectDraftRow() {
        selectedItemIDs = []
        selectionAnchorID = nil
        isDrafting = true
    }

    private func handleItemClick(_ item: ShoppingItem) {
        if isDrafting {
            discardDraft()
        }
        let modifiers = currentClickModifiers()
        let ordered = ItemSelection.visualOrderedIDs(
            from: ItemListSections.derive(
                from: filteredItems,
                groupOption: dataStore.groupOption
            )
        )
        let command = modifiers.contains(.command)
        let shift = modifiers.contains(.shift)

        if shift, let anchor = selectionAnchorID {
            let range = ItemSelection.range(from: anchor, to: item.id, in: ordered)
            if command {
                selectedItemIDs.formUnion(range)
            } else {
                selectedItemIDs = Set(range)
            }
        } else if command {
            if selectedItemIDs.contains(item.id) {
                selectedItemIDs.remove(item.id)
            } else {
                selectedItemIDs.insert(item.id)
            }
            selectionAnchorID = item.id
        } else {
            selectedItemIDs = [item.id]
            selectionAnchorID = item.id
        }
    }

    private func currentClickModifiers() -> EventModifiers {
        var mods: EventModifiers = []
        let flags = NSEvent.modifierFlags
        if flags.contains(.shift) { mods.insert(.shift) }
        if flags.contains(.command) { mods.insert(.command) }
        return mods
    }

    private func pruneSelection() {
        let visible = Set(filteredItems.map(\.id))
        selectedItemIDs = ItemSelection.prunedSelection(selectedItemIDs, visibleIDs: visible)
        if let anchor = selectionAnchorID, !selectedItemIDs.contains(anchor) {
            selectionAnchorID = selectedItemIDs.first
        }
    }

    private func handleCompletionKeyPress() -> KeyPress.Result {
        guard !isDetailTextFocused, !isSearchFocused, !isDrafting else {
            return .ignored
        }
        guard selectedItemIDs.count == 1,
              let selectedItemID = selectedItemIDs.first,
              let item = item(for: selectedItemID) else {
            return .ignored
        }
        toggleCompletion(item)
        return .handled
    }

    private func selectAllTagsFilter() {
        dataStore.selectedTags = []
    }

    private func toggleTagFilter(_ id: UUID) {
        if dataStore.selectedTags.contains(id) {
            dataStore.selectedTags.remove(id)
        } else {
            dataStore.selectedTags.insert(id)
        }
    }

    private func toggleCompletion(_ item: ShoppingItem) {
        let willComplete = !item.isCompleted
        dataStore.setCompleted(
            item,
            completed: willComplete,
            presentUndo: undoCoordinator.present
        )
        if willComplete {
            completionHapticToken &+= 1
            ShopHaptics.itemCompleted()
        } else {
            restoreHapticToken &+= 1
            ShopHaptics.itemRestored()
        }
    }

    private func deleteItem(_ item: ShoppingItem) {
        selectedItemIDs.remove(item.id)
        if selectionAnchorID == item.id {
            selectionAnchorID = selectedItemIDs.first
        }
        dataStore.deleteItem(item, presentUndo: undoCoordinator.present)
    }

    private func deleteSelectedItem() {
        guard !isDrafting else {
            discardDraft()
            return
        }
        if selectedItemIDs.count > 1 {
            showBatchDeleteConfirm = true
            return
        }
        guard let selectedItemID = selectedItemIDs.first, let item = item(for: selectedItemID) else { return }
        deleteItem(item)
    }

    private func triggerSync() {
        guard webdavSync.isConfigured, !syncCoordinator.status.isSyncing else { return }
        Task { await performManualSync() }
    }

    /// Shared by pull-to-refresh, ⌘R, and the sidebar sync button.
    private func performManualSync() async {
        guard webdavSync.isConfigured else { return }
        refreshHapticToken &+= 1
        ShopHaptics.pullToRefreshTriggered()
        await syncCoordinator.syncNow()
    }

    private func performUndo() {
        do {
            try undoCoordinator.undo()
        } catch {
            // Undo failures surface through the data store error state.
        }
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
    let selectedItemIDs: Set<UUID>
    let isDrafting: Bool
    let onSelect: (ShoppingItem) -> Void
    let onSelectDraft: () -> Void
    let onToggleCompletion: (ShoppingItem) -> Void
    let onDeleteItem: (ShoppingItem) -> Void
    let onRefresh: () async -> Void

    @EnvironmentObject private var dataStore: DataStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var sections: ItemListSections {
        ItemListSections.derive(
            from: filteredItems,
            groupOption: dataStore.groupOption
        )
    }

    private var canReorder: Bool {
        ItemListReorderPolicy.canReorder(
            filter: dataStore.selectedFilter,
            selectedTags: dataStore.selectedTags,
            dateRange: dataStore.dateRange,
            searchIsActive: searchIsActive,
            sortOption: dataStore.sortOption,
            groupOption: dataStore.groupOption
        )
    }

    private var itemLookup: [UUID: ShoppingItem] {
        Dictionary(uniqueKeysWithValues: filteredItems.map { ($0.id, $0) })
    }

    var body: some View {
        List {
            if isDrafting {
                Section {
                    MacDraftRow()
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onSelectDraft)
                        .listRowBackground(ShopTheme.brandColor.opacity(0.12))
                }
            }

            if sections.isGrouped {
                ForEach(sections.activeGroups) { group in
                    Section {
                        ForEach(group.itemIDs, id: \.self) { itemID in
                            if let item = itemLookup[itemID] {
                                row(for: item)
                            }
                        }
                    } header: {
                        Text(group.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(nil)
                    }
                }
            } else if !sections.activeIDs.isEmpty {
                Section {
                    activeRows
                }
            }

            if sections.showsArchiveSection {
                Section {
                    ForEach(sections.archivedIDs, id: \.self) { itemID in
                        if let item = itemLookup[itemID] {
                            row(for: item)
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
        .macPullToRefresh {
            await onRefresh()
        }
        .animation(reduceMotion ? nil : .default, value: sections.displayRows)
    }

    @ViewBuilder
    private var activeRows: some View {
        let rows = ForEach(sections.activeIDs, id: \.self) { itemID in
            if let item = itemLookup[itemID] {
                row(for: item)
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
            isSelected: selectedItemIDs.contains(item.id),
            onToggleCompletion: { onToggleCompletion(item) },
            onSelect: { onSelect(item) }
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDeleteItem(item)
            } label: {
                Label(ShopStrings.deleteItem, systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                onToggleCompletion(item)
            } label: {
                Label(
                    item.isCompleted ? ShopStrings.markIncomplete : ShopStrings.markComplete,
                    systemImage: item.isCompleted ? "arrow.uturn.backward" : "checkmark"
                )
            }
            .tint(ShopTheme.brandColor)
        }
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

private struct MacDraftRow: View {
    var body: some View {
        HStack(spacing: ShopTheme.spacingSM + 4) {
            Circle()
                .stroke(Color.secondary.opacity(0.35), lineWidth: 2)
                .frame(width: 20, height: 20)

            Text(String(localized: "mac.draft_placeholder"))
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding(.vertical, ShopTheme.spacingXS)
    }
}

private struct MacItemRow: View {
    let item: ShoppingItem
    let isSelected: Bool
    let onToggleCompletion: () -> Void
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: ShopTheme.spacingSM + 4) {
            Button(action: onToggleCompletion) {
                MacCompletionControl(isCompleted: item.isCompleted)
            }
            .buttonStyle(.plain)
            .help(item.isCompleted ? ShopStrings.markIncomplete : ShopStrings.markComplete)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: ShopTheme.spacingXS) {
                    Text(item.name)
                        .font(.body.weight(.semibold))
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
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)
        }
        .padding(.vertical, ShopTheme.spacingXS)
        .listRowBackground(
            isSelected
                ? ShopTheme.brandColor.opacity(0.12)
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
                    isCompleted ? ShopTheme.brandColor : Color.secondary.opacity(0.35),
                    lineWidth: 2
                )
                .frame(width: 20, height: 20)

            if isCompleted {
                Circle()
                    .fill(ShopTheme.brandColor)
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

// MARK: - Draft Detail

private struct MacBatchDetailView: View {
    let selectedItemIDs: Set<UUID>
    let onComplete: () -> Void
    let onRestore: () -> Void
    let onDelete: () -> Void

    @EnvironmentObject private var dataStore: DataStore
    @EnvironmentObject private var undoCoordinator: UndoCoordinator

    private var selectedItems: [ShoppingItem] {
        dataStore.items.filter { selectedItemIDs.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ShopTheme.spacingMD) {
                Text(ShopStrings.selectionCount(selectedItemIDs.count))
                    .font(.title2.weight(.semibold))

                VStack(alignment: .leading, spacing: ShopTheme.spacingSM) {
                    Button(action: onComplete) {
                        Label(ShopStrings.selectionMarkAllComplete, systemImage: "checkmark.circle")
                    }
                    Button(action: onRestore) {
                        Label(ShopStrings.selectionMarkAllIncomplete, systemImage: "arrow.uturn.backward.circle")
                    }
                    Button(role: .destructive, action: onDelete) {
                        Label(ShopStrings.deleteItem, systemImage: "trash")
                    }
                }
                .buttonStyle(.bordered)

                Divider()

                Text(ShopStrings.selectionEditTags)
                    .font(.headline)

                ForEach(dataStore.tags, id: \.id) { tag in
                    let membership = ItemSelection.membership(
                        of: tag.id,
                        in: selectedItems.map { ($0.id, Set($0.tags.map(\.id))) }
                    )
                    Button {
                        apply(tag: tag, membership: membership)
                    } label: {
                        HStack {
                            Circle()
                                .fill(tag.displayColor)
                                .frame(width: 10, height: 10)
                            Text(tag.name)
                            Spacer()
                            Image(systemName: symbol(for: membership))
                                .foregroundStyle(ShopTheme.brandColor)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(accessibility(for: membership))
                    .accessibilityLabel(tag.name)
                    .accessibilityValue(accessibility(for: membership))
                }
            }
            .padding(ShopTheme.spacingMD)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func symbol(for membership: TagMembership) -> String {
        switch membership {
        case .all: "checkmark.circle.fill"
        case .some: "minus.circle.fill"
        case .none: "circle"
        }
    }

    private func accessibility(for membership: TagMembership) -> String {
        switch membership {
        case .all: ShopStrings.selectionTagAll
        case .some: ShopStrings.selectionTagSome
        case .none: ShopStrings.selectionTagNone
        }
    }

    private func apply(tag: Tag, membership: TagMembership) {
        let ids = Array(selectedItemIDs)
        switch membership {
        case .all:
            dataStore.removeTag(tag, fromItemIDs: ids, presentUndo: undoCoordinator.present)
        case .some, .none:
            dataStore.addTag(tag, toItemIDs: ids, presentUndo: undoCoordinator.present)
        }
        ShopHaptics.itemRestored()
    }
}

private struct MacDraftDetailView: View {
    @Binding var draftName: String
    @Binding var draftSelectedTags: Set<UUID>
    @Binding var draftCreatedAt: Date
    @Binding var isTextFocused: Bool
    let onSave: () -> Void
    let onDiscard: () -> Void

    @EnvironmentObject private var dataStore: DataStore
    @FocusState private var isNameFocused: Bool

    var body: some View {
        Form {
            Section {
                TextField(ShopStrings.itemName, text: $draftName)
                    .focused($isNameFocused)
                    .onSubmit(onSave)
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
                DatePicker(
                    ShopStrings.addedAt,
                    selection: $draftCreatedAt,
                    displayedComponents: [.date, .hourAndMinute]
                )
            }

            Section {
                Button(ShopStrings.saveItem, action: onSave)
                    .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button(ShopStrings.discardChanges, role: .destructive, action: onDiscard)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(ShopStrings.addItem)
        .onAppear {
            isNameFocused = true
            isTextFocused = true
        }
        .onChange(of: isNameFocused) { _, focused in
            isTextFocused = focused
        }
    }

    private func tagBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { draftSelectedTags.contains(id) },
            set: { isOn in
                var next = draftSelectedTags
                if isOn {
                    next.insert(id)
                } else {
                    next.remove(id)
                }
                draftSelectedTags = next
            }
        )
    }
}

// MARK: - Detail Editor

private struct MacItemDetailView: View {
    let itemID: UUID
    @Binding var isTextFocused: Bool

    @EnvironmentObject private var dataStore: DataStore

    @State private var itemName = ""
    @State private var selectedTags: Set<UUID> = []
    @State private var createdAt = Date()
    @State private var completedAt = Date()
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
                        DatePicker(
                            ShopStrings.addedAt,
                            selection: $createdAt,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        if item.isCompleted {
                            DatePicker(
                                ShopStrings.completedAtLabel,
                                selection: $completedAt,
                                displayedComponents: [.date, .hourAndMinute]
                            )
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
                .onChange(of: createdAt) { _, _ in
                    save(item)
                }
                .onChange(of: completedAt) { _, _ in
                    save(item)
                }
                .onChange(of: isNameFocused) { _, focused in
                    isTextFocused = focused
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
                var next = selectedTags
                if isOn {
                    next.insert(id)
                } else {
                    next.remove(id)
                }
                selectedTags = next
            }
        )
    }

    private func syncFromItem(_ item: ShoppingItem) {
        itemName = item.name
        selectedTags = Set(item.tags.map(\.id))
        createdAt = item.createdAt
        completedAt = item.completedAt ?? item.createdAt
    }

    private func syncFromItemIfNeeded(_ item: ShoppingItem) {
        let storeTags = Set(item.tags.map(\.id))
        let trimmed = itemName.trimmingCharacters(in: .whitespacesAndNewlines)
        let createdMatches = Calendar.current.isDate(createdAt, equalTo: item.createdAt, toGranularity: .minute)
        let completedMatches: Bool
        if item.isCompleted {
            completedMatches = Calendar.current.isDate(
                completedAt,
                equalTo: item.completedAt ?? item.createdAt,
                toGranularity: .minute
            )
        } else {
            completedMatches = true
        }
        if trimmed == item.name, selectedTags == storeTags, createdMatches, completedMatches {
            return
        }
        syncFromItem(item)
    }

    private func save(_ item: ShoppingItem) {
        let trimmed = itemName.trimmingCharacters(in: .whitespacesAndNewlines)
        let tags = dataStore.tags.filter { selectedTags.contains($0.id) }
        let originalTags = Set(item.tags.map(\.id))
        let nameUpdate: String? = {
            guard !trimmed.isEmpty else { return nil }
            return trimmed == item.name ? nil : trimmed
        }()
        let tagsUpdate: [Tag]? = selectedTags == originalTags ? nil : tags
        let createdChanged = !Calendar.current.isDate(createdAt, equalTo: item.createdAt, toGranularity: .minute)
        let completedChanged: Bool
        if item.isCompleted {
            completedChanged = !Calendar.current.isDate(
                completedAt,
                equalTo: item.completedAt ?? item.createdAt,
                toGranularity: .minute
            )
        } else {
            completedChanged = false
        }
        guard nameUpdate != nil || tagsUpdate != nil || createdChanged || completedChanged else { return }
        dataStore.updateItem(
            item,
            name: nameUpdate,
            tags: tagsUpdate,
            createdAt: createdChanged ? createdAt : nil,
            completedAt: item.isCompleted && completedChanged ? completedAt : nil,
            updateCompletedAt: item.isCompleted && completedChanged
        )
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
/// macOS `.refreshable` mainly wires ⌘R / View → Refresh, not trackpad pull.
/// This adds an actual overscroll-triggered refresh for List / ScrollView.
private struct MacPullToRefreshModifier: ViewModifier {
    let onRefresh: () async -> Void

    @State private var isRefreshing = false
    @State private var hasArmed = false
    @State private var pullDistance: CGFloat = 0

    /// Keep below typical macOS rubber-band travel; old 52pt often never fired.
    private let armThreshold: CGFloat = 20
    private let releaseThreshold: CGFloat = 10

    func body(content: Content) -> some View {
        content
            .scrollBounceBehavior(.always)
            .refreshable {
                await onRefresh()
            }
            .overlay(alignment: .top) {
                if isRefreshing || hasArmed {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.top, 10)
                        .allowsHitTesting(false)
                }
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                // Rubber-banding past the top makes contentOffset.y negative on macOS List/ScrollView.
                -geometry.contentOffset.y
            } action: { _, rawOverscroll in
                let distance = max(0, rawOverscroll)
                pullDistance = distance

                if !isRefreshing && !hasArmed && distance >= armThreshold {
                    hasArmed = true
                    ShopHaptics.pullToRefreshArmed()
                }

                // Fire on release after a deep enough pull — not on every bounce frame.
                if hasArmed && !isRefreshing && distance < releaseThreshold {
                    hasArmed = false
                    isRefreshing = true
                    Task { @MainActor in
                        await onRefresh()
                        isRefreshing = false
                        pullDistance = 0
                    }
                }

                if !hasArmed && !isRefreshing && distance < releaseThreshold {
                    pullDistance = 0
                }
            }
    }
}

private extension View {
    func macPullToRefresh(action: @escaping () async -> Void) -> some View {
        modifier(MacPullToRefreshModifier(onRefresh: action))
    }
}

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

private extension DataStore.SortOption {
    var macTitle: String {
        switch self {
        case .manual: ShopStrings.sortManual
        case .createdNewest: ShopStrings.sortCreatedNewest
        case .createdOldest: ShopStrings.sortCreatedOldest
        case .nameAscending: ShopStrings.sortNameAscending
        case .nameDescending: ShopStrings.sortNameDescending
        }
    }
}

private extension DataStore.GroupOption {
    var macTitle: String {
        switch self {
        case .none: ShopStrings.groupNone
        case .byTagSet: ShopStrings.groupByTagSet
        case .byPrimaryTag: ShopStrings.groupByPrimaryTag
        case .byEachTag: ShopStrings.groupByEachTag
        }
    }
}
