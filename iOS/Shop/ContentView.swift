import SwiftUI
import ShopCore

struct ContentView: View {
    @EnvironmentObject var dataStore: DataStore
    @State private var showAddSheet = false
    @State private var showSettings = false
    @State private var showFilter = false
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                // Liquid Glass background
                LiquidGlassBackground()

                VStack(spacing: 0) {
                    // Search bar
                    if !dataStore.items.isEmpty {
                        SearchBar(text: $searchText)
                            .padding(.horizontal)
                            .padding(.top, 8)
                    }

                    // Active filter chips
                    if dataStore.selectedFilter != .all || !dataStore.selectedTags.isEmpty {
                        ActiveFilterBar(
                            currentFilter: $dataStore.selectedFilter,
                            selectedTags: $dataStore.selectedTags,
                            allTags: dataStore.tags
                        )
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                    }

                    // Item list
                    if filteredItems.isEmpty {
                        EmptyStateView(showAddSheet: $showAddSheet)
                    } else {
                        ItemListView(items: filteredItems)
                    }
                }
            }
            .navigationTitle(ShopStrings.appName)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showFilter.toggle()
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .symbolVariant(dataStore.selectedFilter != .all || !dataStore.selectedTags.isEmpty ? .fill : .none)
                            .font(.title3)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            showSettings.toggle()
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.title3)
                        }
                        Button {
                            showAddSheet.toggle()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .symbolRenderingMode(.hierarchical)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddItemView()
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(32)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .presentationCornerRadius(32)
        }
        .sheet(isPresented: $showFilter) {
            FilterView()
                .presentationDetents([.medium])
                .presentationCornerRadius(32)
        }
    }

    private var filteredItems: [ShoppingItem] {
        let filtered = dataStore.filteredItems
        guard !searchText.isEmpty else { return filtered }
        return filtered.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
}
