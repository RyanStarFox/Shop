import SwiftUI
import ShopCore

struct ContentView: View {
    @EnvironmentObject private var dataStore: DataStore
    @EnvironmentObject private var undoCoordinator: UndoCoordinator

    @State private var editorMode: ItemEditorView.Mode?
    @State private var showSettings = false
    @State private var showFilter = false
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ShopSurfaceBackground()

                VStack(spacing: 0) {
                    if hasAnyItems {
                        SearchBar(text: $searchText)
                            .padding(.horizontal, ShopTheme.spacingMD)
                            .padding(.top, ShopTheme.spacingSM)
                    }

                    if dataStore.selectedFilter != .all || !dataStore.selectedTags.isEmpty {
                        ActiveFilterBar(
                            currentFilter: $dataStore.selectedFilter,
                            selectedTags: $dataStore.selectedTags,
                            allTags: dataStore.tags
                        )
                        .padding(.horizontal, ShopTheme.spacingMD)
                        .padding(.vertical, ShopTheme.spacingXS + 2)
                    }

                    if filteredItems.isEmpty {
                        EmptyStateView {
                            editorMode = .add
                        }
                    } else {
                        ItemListView(
                            filteredItems: filteredItems,
                            onEditItem: { item in
                                editorMode = .edit(item)
                            }
                        )
                    }
                }

                UndoBanner(undoCoordinator: undoCoordinator)
            }
            .navigationTitle(ShopStrings.appName)
            .modifier(PendingCountSubtitle(count: dataStore.activeItems.count))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showFilter.toggle()
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .symbolVariant(
                                dataStore.selectedFilter != .all || !dataStore.selectedTags.isEmpty
                                    ? .fill
                                    : .none
                            )
                    }
                    .frame(minWidth: ShopTheme.minTouchTarget, minHeight: ShopTheme.minTouchTarget)
                    .accessibilityLabel(ShopStrings.filter)
                    .accessibilityHint(ShopStrings.filter)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: ShopTheme.spacingSM + 4) {
                        Button {
                            showSettings.toggle()
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .frame(minWidth: ShopTheme.minTouchTarget, minHeight: ShopTheme.minTouchTarget)
                        .accessibilityLabel(ShopStrings.settings)

                        Button {
                            editorMode = .add
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .symbolRenderingMode(.hierarchical)
                        }
                        .frame(minWidth: ShopTheme.minTouchTarget, minHeight: ShopTheme.minTouchTarget)
                        .accessibilityLabel(ShopStrings.addItem)
                    }
                }
            }
        }
        .tint(ShopTheme.naturalGreen)
        .sheet(item: $editorMode) { mode in
            ItemEditorView(mode: mode)
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(ShopTheme.spacingLG)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .presentationCornerRadius(ShopTheme.spacingLG)
        }
        .sheet(isPresented: $showFilter) {
            FilterView()
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(ShopTheme.spacingLG)
        }
    }

    private var hasAnyItems: Bool {
        !dataStore.items.isEmpty
    }

    private var filteredItems: [ShoppingItem] {
        let filtered = dataStore.filteredItems
        guard !searchText.isEmpty else { return filtered }
        return filtered.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
}

extension ItemEditorView.Mode: Identifiable {
    var id: String {
        switch self {
        case .add:
            "add"
        case .edit(let item):
            item.id.uuidString
        }
    }
}

private struct PendingCountSubtitle: ViewModifier {
    let count: Int

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.navigationSubtitle(
                count == 0 ? "" : ShopStrings.pendingCount(count)
            )
        } else {
            content
        }
    }
}
