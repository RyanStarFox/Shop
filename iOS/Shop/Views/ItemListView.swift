import SwiftUI
import ShopCore

struct ItemListView: View {
    let items: [ShoppingItem]
    @EnvironmentObject var dataStore: DataStore

    var body: some View {
        List {
            ForEach(items) { item in
                ItemRow(item: item)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            withAnimation {
                                dataStore.deleteItem(item)
                            }
                        } label: {
                            Label(ShopStrings.deleteItem, systemImage: "trash")
                        }
                    }
            }
            .onDelete { offsets in
                let mapped = offsets.compactMap { offset in
                    items.firstIndex { $0.id == items[offset].id }
                }
                for idx in mapped {
                    dataStore.deleteItem(items[idx])
                }
            }
            .onMove { source, destination in
                dataStore.moveItems(from: source, to: destination)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Item Row

struct ItemRow: View {
    let item: ShoppingItem
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                dataStore.toggleItem(item)
            }
        } label: {
            HStack(spacing: 14) {
                // Checkbox
                ZStack {
                    Circle()
                        .stroke(item.isCompleted ? .green : .secondary.opacity(0.4), lineWidth: 2)
                        .frame(width: 24, height: 24)

                    if item.isCompleted {
                        Circle()
                            .fill(.green.gradient)
                            .frame(width: 24, height: 24)
                        Image(systemName: "checkmark")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                    }
                }

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.body)
                        .foregroundStyle(item.isCompleted ? .secondary : .primary)
                        .strikethrough(item.isCompleted, pattern: .solid, color: .secondary)

                    HStack(spacing: 6) {
                        // Time
                        Label(
                            ShopStrings.relativeTime(from: item.createdAt),
                            systemImage: "clock"
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                        // Tags
                        ForEach(item.tags, id: \.id) { tag in
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(tag.displayColor)
                                    .frame(width: 6, height: 6)
                                Text(tag.name)
                                    .font(.caption2)
                                    .foregroundStyle(tag.displayColor)
                            }
                        }
                    }
                }

                Spacer()

                Image(systemName: "line.3.horizontal")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}
