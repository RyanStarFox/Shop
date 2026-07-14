import SwiftUI
import ShopCore

struct WatchContentView: View {
    @EnvironmentObject var dataStore: DataStore
    @State private var showAddSheet = false

    var body: some View {
        NavigationStack {
            List {
                if dataStore.filteredItems.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "cart")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text(ShopStrings.emptyList)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .padding(.vertical, 20)
                } else {
                    ForEach(dataStore.filteredItems) { item in
                        Button {
                            withAnimation {
                                dataStore.toggleItem(item)
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(item.isCompleted ? .green : .secondary)
                                    .font(.title3)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(.body)
                                        .strikethrough(item.isCompleted)
                                        .foregroundStyle(item.isCompleted ? .secondary : .primary)
                                        .lineLimit(2)

                                    if !item.tags.isEmpty {
                                        Text(item.tags.map(\.name).joined(separator: ", "))
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.ultraThinMaterial)
                                .padding(2)
                        )
                    }
                }
            }
            .navigationTitle(ShopStrings.appName)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                WatchAddItemView()
            }
        }
    }
}
