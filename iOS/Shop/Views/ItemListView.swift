import SwiftUI
import ShopCore

struct ItemListView: View {
    let filteredItems: [ShoppingItem]
    let searchIsActive: Bool
    let isSelecting: Bool
    @Binding var selectedItemIDs: Set<UUID>
    let onEnterSelection: (ShoppingItem) -> Void
    let onEditItem: (ShoppingItem) -> Void

    @EnvironmentObject private var dataStore: DataStore
    @EnvironmentObject private var undoCoordinator: UndoCoordinator
    @EnvironmentObject private var syncCoordinator: SyncCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var sections: ItemListSections {
        ItemListSections.derive(
            from: filteredItems,
            groupOption: dataStore.groupOption
        )
    }

    private var canReorder: Bool {
        !isSelecting && ItemListReorderPolicy.canReorder(
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
            if sections.isGrouped {
                ForEach(sections.activeGroups) { group in
                    Section {
                        ForEach(group.itemIDs, id: \.self) { itemID in
                            if let item = itemLookup[itemID] {
                                itemRow(item)
                            }
                        }
                    } header: {
                        Text(group.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(nil)
                            .accessibilityAddTraits(.isHeader)
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
        .refreshable {
            await syncCoordinator.syncNowIfConfigured()
        }
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
        let isSelected = selectedItemIDs.contains(item.id)
        ItemRow(
            item: item,
            isSelecting: isSelecting,
            isSelected: isSelected,
            onToggleCompletion: { toggleCompletion(for: item) },
            onEdit: { onEditItem(item) },
            onToggleSelection: { toggleSelection(for: item) }
        )
        .listRowBackground(Color.clear)
        .listRowSeparator(.visible)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onLongPressGesture {
            guard !isSelecting else { return }
            onEnterSelection(item)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !isSelecting {
                Button(role: .destructive) {
                    deleteItem(item)
                } label: {
                    Label(ShopStrings.deleteItem, systemImage: "trash")
                }
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if !isSelecting {
                Button {
                    toggleCompletion(for: item)
                } label: {
                    Label(
                        item.isCompleted ? ShopStrings.markIncomplete : ShopStrings.markComplete,
                        systemImage: item.isCompleted ? "arrow.uturn.backward" : "checkmark"
                    )
                }
                .tint(ShopTheme.brandColor)
            }
        }
    }

    private func toggleSelection(for item: ShoppingItem) {
        if selectedItemIDs.contains(item.id) {
            selectedItemIDs.remove(item.id)
        } else {
            selectedItemIDs.insert(item.id)
        }
        ShopHaptics.itemRestored()
    }

    private func toggleCompletion(for item: ShoppingItem) {
        let willComplete = !item.isCompleted
        withAnimation(reduceMotion ? nil : .default) {
            dataStore.setCompleted(
                item,
                completed: willComplete,
                presentUndo: undoCoordinator.present
            )
        }
        if willComplete {
            ShopHaptics.itemCompleted()
        } else {
            ShopHaptics.itemRestored()
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
    let isSelecting: Bool
    let isSelected: Bool
    let onToggleCompletion: () -> Void
    let onEdit: () -> Void
    let onToggleSelection: () -> Void

    var body: some View {
        HStack(spacing: ShopTheme.spacingSM + 4) {
            if isSelecting {
                Button(action: onToggleSelection) {
                    SelectionControl(isSelected: isSelected)
                }
                .buttonStyle(.plain)
                .frame(minWidth: ShopTheme.minTouchTarget, minHeight: ShopTheme.minTouchTarget)
            } else {
                Button(action: onToggleCompletion) {
                    CompletionControl(isCompleted: item.isCompleted)
                }
                .buttonStyle(.plain)
                .frame(minWidth: ShopTheme.minTouchTarget, minHeight: ShopTheme.minTouchTarget)
                .accessibilityLabel(
                    item.isCompleted ? ShopStrings.markIncomplete : ShopStrings.markComplete
                )
            }

            Button(action: {
                if isSelecting {
                    onToggleSelection()
                } else {
                    onEdit()
                }
            }) {
                HStack(alignment: .top, spacing: ShopTheme.spacingSM) {
                    VStack(alignment: .leading, spacing: ShopTheme.spacingXS) {
                        Text(item.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(item.isCompleted ? .secondary : .primary)
                            .strikethrough(item.isCompleted, color: .secondary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if !item.tags.isEmpty {
                            TagRow(tags: item.tags)
                        }
                    }

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(item.createdAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        if item.isCompleted, let completedAt = item.completedAt {
                            Text(completedAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(dateAccessibilityLabel)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(minHeight: ShopTheme.minTouchTarget)
            .accessibilityLabel(itemAccessibilityLabel)
            .accessibilityHint(isSelecting ? ShopStrings.selectionSelect : ShopStrings.editItem)
        }
        .padding(.vertical, ShopTheme.spacingXS)
    }

    private var dateAccessibilityLabel: String {
        var parts = ["\(ShopStrings.addedAt) \(item.createdAt.formatted(date: .abbreviated, time: .omitted))"]
        if item.isCompleted, let completedAt = item.completedAt {
            parts.append("\(ShopStrings.completedAtLabel) \(completedAt.formatted(date: .abbreviated, time: .omitted))")
        }
        return parts.joined(separator: ", ")
    }

    private var itemAccessibilityLabel: String {
        let status = item.isCompleted ? ShopStrings.filterCompleted : ShopStrings.filterActive
        let tagNames = item.tags.map(\.name).joined(separator: ", ")
        if tagNames.isEmpty {
            return "\(item.name), \(status), \(dateAccessibilityLabel)"
        }
        return "\(item.name), \(tagNames), \(status), \(dateAccessibilityLabel)"
    }
}

private struct SelectionControl: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    isSelected ? ShopTheme.brandColor : Color.secondary.opacity(0.35),
                    lineWidth: 2
                )
                .frame(width: 24, height: 24)

            if isSelected {
                Circle()
                    .fill(ShopTheme.brandColor)
                    .frame(width: 24, height: 24)
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
            }
        }
    }
}

private struct CompletionControl: View {
    let isCompleted: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    isCompleted ? ShopTheme.brandColor : Color.secondary.opacity(0.35),
                    lineWidth: 2
                )
                .frame(width: 24, height: 24)

            if isCompleted {
                Circle()
                    .fill(ShopTheme.brandColor)
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
