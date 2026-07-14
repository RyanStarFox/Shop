import SwiftUI
import ShopCore

struct MacContentView: View {
    @EnvironmentObject var dataStore: DataStore
    @EnvironmentObject var webdavSync: WebDAVSyncService
    @State private var newItemName = ""
    @State private var selectedFilter = DataStore.FilterOption.all
    @State private var selectedItem: ShoppingItem? = nil
    @State private var searchText = ""
    @FocusState private var isAddFocused: Bool

    var body: some View {
        NavigationSplitView {
            // Sidebar
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 250)
        } detail: {
            // Detail
            detailView
        }
        .background(VisualEffectView(material: .windowBackground, blendingMode: .behindWindow))
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            // Quick-add bar
            quickAddBar
                .padding(12)

            Divider()

            // Filter sections
            List(selection: $selectedFilter) {
                Section(ShopStrings.filter) {
                    ForEach(DataStore.FilterOption.allCases, id: \.self) { option in
                        Label(filterLabel(for: option), systemImage: iconForFilter(option))
                            .tag(option)
                    }
                }

                if !dataStore.tags.isEmpty {
                    Section(ShopStrings.tags) {
                        ForEach(dataStore.tags) { tag in
                            HStack {
                                Circle()
                                    .fill(tag.displayColor)
                                    .frame(width: 10, height: 10)
                                Text(tag.name)
                            }
                            .onTapGesture {
                                if dataStore.selectedTags.contains(tag.id) {
                                    dataStore.selectedTags.remove(tag.id)
                                } else {
                                    dataStore.selectedTags.insert(tag.id)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            // Sync status
            syncStatusBar
                .padding(12)
        }
        .onChange(of: selectedFilter) { _, newFilter in
            dataStore.selectedFilter = newFilter
        }
    }

    // MARK: - Quick Add Bar

    private var quickAddBar: some View {
        HStack(spacing: 8) {
            TextField(ShopStrings.addItem, text: $newItemName)
                .textFieldStyle(.roundedBorder)
                .focused($isAddFocused)
                .onSubmit {
                    addItem()
                }

            Button {
                addItem()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(newItemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .keyboardShortcut(.return, modifiers: [.command])
        }
    }

    // MARK: - Detail View

    private var detailView: some View {
        VStack(spacing: 0) {
            if !dataStore.items.isEmpty {
                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(ShopStrings.itemSearch, text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(10)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(12)
            }

            if filteredItems.isEmpty {
                emptyDetail
            } else {
                // Item list
                List {
                    ForEach(filteredItems) { item in
                        MacItemRow(item: item)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3)) {
                                    dataStore.toggleItem(item)
                                }
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    dataStore.deleteItem(item)
                                } label: {
                                    Label(ShopStrings.deleteItem, systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }

            // Status bar
            HStack {
                Text("\(dataStore.filteredItems.count) items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if webdavSync.isSyncing {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
    }

    // MARK: - Empty Detail

    private var emptyDetail: some View {
        VStack(spacing: 16) {
            Image(systemName: "cart")
                .font(.system(size: 56))
                .foregroundStyle(.secondary.opacity(0.5))

            Text(ShopStrings.emptyList)
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("Press ⌘N to add an item")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Sync Status Bar

    private var syncStatusBar: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(webdavSync.isConfigured ? Color.green : Color.secondary)
                .frame(width: 6, height: 6)

            Text(webdavSync.isConfigured
                ? ShopStrings.webdavConfigured
                : ShopStrings.webdavNotConfigured
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer()

            if webdavSync.isConfigured {
                Button {
                    Task { await webdavSync.autoSync() }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .disabled(webdavSync.isSyncing)
            }
        }
    }

    // MARK: - Helpers

    private var filteredItems: [ShoppingItem] {
        let filtered = dataStore.filteredItems
        guard !searchText.isEmpty else { return filtered }
        return filtered.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private func addItem() {
        let name = newItemName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        dataStore.addItem(name: name)
        newItemName = ""
    }

    private func filterLabel(for opt: DataStore.FilterOption) -> String {
        switch opt {
        case .all: return ShopStrings.filterAll
        case .active: return ShopStrings.filterActive
        case .completed: return ShopStrings.filterCompleted
        case .today: return ShopStrings.filterToday
        case .week: return ShopStrings.filterWeek
        case .month: return ShopStrings.filterMonth
        }
    }

    private func iconForFilter(_ opt: DataStore.FilterOption) -> String {
        switch opt {
        case .all: return "list.bullet"
        case .active: return "circle"
        case .completed: return "checkmark.circle"
        case .today: return "calendar"
        case .week: return "calendar.badge.clock"
        case .month: return "calendar"
        }
    }
}

// MARK: - Mac Item Row

struct MacItemRow: View {
    let item: ShoppingItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(item.isCompleted ? .green : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)

                HStack(spacing: 6) {
                    Text(ShopStrings.relativeTime(from: item.createdAt))
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    ForEach(item.tags, id: \.id) { tag in
                        HStack(spacing: 2) {
                            Circle()
                                .fill(tag.displayColor)
                                .frame(width: 6, height: 6)
                            Text(tag.name)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            Spacer()

            if item.isCompleted, let completedAt = item.completedAt {
                Text(completedAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - NSVisualEffectView wrapper for macOS

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
