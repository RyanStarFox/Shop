import SwiftUI
import ShopCore

struct ItemListView: View {
    let filteredItems: [ShoppingItem]
    let onEditItem: (ShoppingItem) -> Void

    @EnvironmentObject private var dataStore: DataStore
    @EnvironmentObject private var undoCoordinator: UndoCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var sections: ItemListSections {
        ItemListSections.derive(from: filteredItems)
    }

    private var canReorder: Bool {
        ItemListReorderPolicy.canReorder(
            filter: dataStore.selectedFilter,
            selectedTags: dataStore.selectedTags,
            dateRange: dataStore.dateRange
        )
    }

    private var itemLookup: [UUID: ShoppingItem] {
        Dictionary(uniqueKeysWithValues: filteredItems.map { ($0.id, $0) })
    }

    var body: some View {
        List {
            if !sections.activeIDs.isEmpty {
                Section {
                    activeRows
                }
            }

            if sections.showsArchiveSection {
                Section {
                    ForEach(sections.archivedIDs, id: \.self) { itemID in
                        if let item = itemLookup[itemID] {
                            itemRow(item)
                        }
                    }
                } header: {
                    Text(ShopStrings.archiveSection)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                        .accessibilityAddTraits(.isHeader)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .animation(reduceMotion ? nil : .default, value: sections.displayRows)
    }

    @ViewBuilder
    private var activeRows: some View {
        let rows = ForEach(sections.activeIDs, id: \.self) { itemID in
            if let item = itemLookup[itemID] {
                itemRow(item)
            }
        }
        if canReorder {
            rows.onMove(perform: moveActiveItems)
        } else {
            rows
        }
    }

    @ViewBuilder
    private func itemRow(_ item: ShoppingItem) -> some View {
        ItemRow(
            item: item,
            onToggleCompletion: { toggleCompletion(for: item) },
            onEdit: { onEditItem(item) }
        )
        .listRowBackground(Color.clear)
        .listRowSeparator(.visible)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                toggleCompletion(for: item)
            } label: {
                Label(
                    item.isCompleted ? ShopStrings.markIncomplete : ShopStrings.markComplete,
                    systemImage: item.isCompleted ? "arrow.uturn.backward" : "checkmark"
                )
            }
            .tint(ShopTheme.naturalGreen)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                toggleCompletion(for: item)
            } label: {
                Label(
                    item.isCompleted ? ShopStrings.markIncomplete : ShopStrings.markComplete,
                    systemImage: item.isCompleted ? "arrow.uturn.backward" : "checkmark"
                )
            }
            .tint(ShopTheme.naturalGreen)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                deleteItem(item)
            } label: {
                Label(ShopStrings.deleteItem, systemImage: "trash")
            }
        }
    }

    private func toggleCompletion(for item: ShoppingItem) {
        withAnimation(reduceMotion ? nil : .default) {
            dataStore.setCompleted(
                item,
                completed: !item.isCompleted,
                presentUndo: undoCoordinator.present
            )
        }
    }

    private func deleteItem(_ item: ShoppingItem) {
        withAnimation(reduceMotion ? nil : .default) {
            dataStore.deleteItem(item, presentUndo: undoCoordinator.present)
        }
    }

    private func moveActiveItems(from source: IndexSet, to destination: Int) {
        dataStore.moveItems(from: source, to: destination)
    }
}

// MARK: - Item Row

struct ItemRow: View {
    let item: ShoppingItem
    let onToggleCompletion: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: ShopTheme.spacingSM + 4) {
            Button(action: onToggleCompletion) {
                CompletionControl(isCompleted: item.isCompleted)
            }
            .buttonStyle(.plain)
            .frame(minWidth: ShopTheme.minTouchTarget, minHeight: ShopTheme.minTouchTarget)
            .accessibilityLabel(
                item.isCompleted ? ShopStrings.markIncomplete : ShopStrings.markComplete
            )

            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: ShopTheme.spacingXS) {
                    Text(item.name)
                        .font(.body)
                        .foregroundStyle(item.isCompleted ? .secondary : .primary)
                        .strikethrough(item.isCompleted, color: .secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !item.tags.isEmpty {
                        TagRow(tags: item.tags)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(minHeight: ShopTheme.minTouchTarget)
            .accessibilityLabel(itemAccessibilityLabel)
            .accessibilityHint(ShopStrings.editItem)
        }
        .padding(.vertical, ShopTheme.spacingXS)
    }

    private var itemAccessibilityLabel: String {
        let status = item.isCompleted ? ShopStrings.filterCompleted : ShopStrings.filterActive
        let tagNames = item.tags.map(\.name).joined(separator: ", ")
        if tagNames.isEmpty {
            return "\(item.name), \(status)"
        }
        return "\(item.name), \(tagNames), \(status)"
    }
}

private struct CompletionControl: View {
    let isCompleted: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    isCompleted ? ShopTheme.naturalGreen : Color.secondary.opacity(0.35),
                    lineWidth: 2
                )
                .frame(width: 24, height: 24)

            if isCompleted {
                Circle()
                    .fill(ShopTheme.naturalGreen)
                    .frame(width: 24, height: 24)
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
            }
        }
    }
}

private struct TagRow: View {
    let tags: [Tag]

    var body: some View {
        FlowLayout(spacing: ShopTheme.spacingXS) {
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

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(size)
            )
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}
