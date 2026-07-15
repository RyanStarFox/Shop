import SwiftUI
import ShopCore

struct ContentView: View {
    @EnvironmentObject private var dataStore: DataStore
    @EnvironmentObject private var undoCoordinator: UndoCoordinator

    @AppStorage("appearance_mode") private var appearanceMode = AppearancePreference.system.rawValue
    @State private var editorMode: ItemEditorView.Mode?
    @State private var showSettings = false
    @State private var showFilter = false
    @State private var searchText = ""
    @State private var undoError: String?

    var body: some View {
        NavigationStack {
            ShopSurfaceBackground()
                .overlay {
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
                                searchIsActive: !searchText.isEmpty,
                                onEditItem: { item in
                                    editorMode = .edit(item)
                                }
                            )
                        }
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    HStack {
                        Spacer(minLength: 0)
                        Button {
                            editorMode = .add
                        } label: {
                            Image(systemName: "plus")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 56, height: 56)
                                .background(ShopTheme.brandRed, in: Circle())
                                .shadow(color: ShopTheme.brandRed.opacity(0.35), radius: 10, y: 4)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(ShopStrings.addItem)
                        Spacer(minLength: 0)
                    }
                    .padding(.bottom, ShopTheme.spacingSM)
                }
                .navigationTitle(ShopStrings.appName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        HStack(spacing: ShopTheme.spacingXS) {
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
                            .accessibilityLabel(ShopStrings.filter)

                            Menu {
                                Section(ShopStrings.sort) {
                                    ForEach(DataStore.SortOption.allCases, id: \.self) { option in
                                        Button {
                                            dataStore.sortOption = option
                                        } label: {
                                            if dataStore.sortOption == option {
                                                Label(option.title, systemImage: "checkmark")
                                            } else {
                                                Text(option.title)
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
                                                Label(option.title, systemImage: "checkmark")
                                            } else {
                                                Text(option.title)
                                            }
                                        }
                                    }
                                }
                            } label: {
                                Image(systemName: "arrow.up.arrow.down.circle")
                                    .symbolVariant(
                                        dataStore.sortOption == .manual && dataStore.groupOption == .none
                                            ? .none
                                            : .fill
                                    )
                            }
                            .accessibilityLabel("\(ShopStrings.sort), \(ShopStrings.group)")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: ShopTheme.spacingSM) {
                            Button {
                                performUndo()
                            } label: {
                                Image(systemName: "arrow.uturn.backward")
                            }
                            .disabled(undoCoordinator.currentAction == nil)
                            .accessibilityLabel(ShopStrings.undo)
                            .accessibilityValue(undoCoordinator.currentAction?.message ?? "")

                            Button {
                                showSettings.toggle()
                            } label: {
                                Image(systemName: "gearshape")
                            }
                            .accessibilityLabel(ShopStrings.settings)
                        }
                    }
                }
                .alert(ShopStrings.undo, isPresented: Binding(
                    get: { undoError != nil },
                    set: { if !$0 { undoError = nil } }
                )) {
                    Button(ShopStrings.dismiss, role: .cancel) {}
                } message: {
                    Text(undoError ?? "")
                }
        }
        .tint(ShopTheme.brandRed)
        .sheet(item: $editorMode) { mode in
            ItemEditorView(mode: mode)
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(ShopTheme.spacingLG)
                .preferredColorScheme(
                    AppearancePreference(storageValue: appearanceMode).colorScheme
                )
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .presentationCornerRadius(ShopTheme.spacingLG)
                .preferredColorScheme(
                    AppearancePreference(storageValue: appearanceMode).colorScheme
                )
        }
        .sheet(isPresented: $showFilter) {
            FilterView()
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(ShopTheme.spacingLG)
                .preferredColorScheme(
                    AppearancePreference(storageValue: appearanceMode).colorScheme
                )
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

    private func performUndo() {
        do {
            try undoCoordinator.undo()
        } catch {
            undoError = error.localizedDescription
        }
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

private extension DataStore.SortOption {
    var title: String {
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
    var title: String {
        switch self {
        case .none: ShopStrings.groupNone
        case .byTagSet: ShopStrings.groupByTagSet
        case .byPrimaryTag: ShopStrings.groupByPrimaryTag
        case .byEachTag: ShopStrings.groupByEachTag
        }
    }
}
