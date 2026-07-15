import SwiftUI
import WatchKit
import ShopCore

struct WatchContentView: View {
    @EnvironmentObject private var dataStore: DataStore
    @EnvironmentObject private var watchSync: WatchSyncService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showAddSheet = false

    private var sections: ItemListSections {
        ItemListSections.derive(from: dataStore.filteredItems)
    }

    private var itemLookup: [UUID: ShoppingItem] {
        Dictionary(uniqueKeysWithValues: dataStore.filteredItems.map { ($0.id, $0) })
    }

    var body: some View {
        NavigationStack {
            List {
                if sections.activeIDs.isEmpty, !sections.showsArchiveSection {
                    emptyState
                } else {
                    if !sections.activeIDs.isEmpty {
                        Section {
                            ForEach(sections.activeIDs, id: \.self) { itemID in
                                if let item = itemLookup[itemID] {
                                    watchItemRow(item)
                                }
                            }
                        }
                    }

                    if sections.showsArchiveSection {
                        Section {
                            ForEach(sections.archivedIDs, id: \.self) { itemID in
                                if let item = itemLookup[itemID] {
                                    watchItemRow(item)
                                }
                            }
                        } header: {
                            Text(ShopStrings.archiveSection)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(nil)
                                .accessibilityAddTraits(.isHeader)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle(ShopStrings.appName)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(ShopStrings.addItem)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                syncFailureBanner
            }
            .sheet(isPresented: $showAddSheet) {
                WatchAddItemView()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: ShopTheme.spacingSM + 4) {
            Image(systemName: "cart")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(ShopStrings.emptyList)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
        .padding(.vertical, ShopTheme.spacingMD)
    }

    @ViewBuilder
    private var syncFailureBanner: some View {
        if let error = watchSync.lastError {
            HStack(spacing: ShopTheme.spacingXS) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                Text(error)
                    .font(.caption2)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ShopTheme.spacingSM)
            .padding(.vertical, ShopTheme.spacingXS)
            .background(.ultraThinMaterial)
            .accessibilityLabel("\(WatchStrings.syncFailed), \(error)")
        }
    }

    @ViewBuilder
    private func watchItemRow(_ item: ShoppingItem) -> some View {
        HStack(alignment: .top, spacing: ShopTheme.spacingSM) {
            Button {
                toggleCompletion(for: item)
            } label: {
                WatchCompletionControl(isCompleted: item.isCompleted)
            }
            .buttonStyle(.plain)
            .frame(
                minWidth: ShopTheme.minTouchTarget,
                minHeight: ShopTheme.minTouchTarget
            )
            .accessibilityLabel(
                item.isCompleted ? ShopStrings.markIncomplete : ShopStrings.markComplete
            )

            VStack(alignment: .leading, spacing: ShopTheme.spacingXS) {
                Text(item.name)
                    .font(.body)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                    .strikethrough(item.isCompleted, color: .secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !item.tags.isEmpty {
                    WatchTagSummary(tags: item.tags)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(itemAccessibilityLabel(for: item))
        }
        .padding(.vertical, ShopTheme.spacingXS)
        .listRowBackground(
            RoundedRectangle(cornerRadius: ShopTheme.rowCornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .padding(2)
        )
    }

    private func itemAccessibilityLabel(for item: ShoppingItem) -> String {
        let status = item.isCompleted ? ShopStrings.filterCompleted : ShopStrings.filterActive
        let tagNames = item.tags.map(\.name).joined(separator: ", ")
        if tagNames.isEmpty {
            return "\(item.name), \(status)"
        }
        return "\(item.name), \(tagNames), \(status)"
    }

    private func toggleCompletion(for item: ShoppingItem) {
        let willComplete = !item.isCompleted
        withAnimation(reduceMotion ? nil : .default) {
            dataStore.setCompleted(
                item,
                completed: willComplete,
                presentUndo: { _ in }
            )
        }
        if willComplete {
            WKInterfaceDevice.current().play(.success)
        } else {
            WKInterfaceDevice.current().play(.click)
        }
    }
}

// MARK: - Completion Control

private struct WatchCompletionControl: View {
    let isCompleted: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    isCompleted ? ShopTheme.naturalGreen : Color.secondary.opacity(0.35),
                    lineWidth: 2
                )
                .frame(width: 22, height: 22)

            if isCompleted {
                Circle()
                    .fill(ShopTheme.naturalGreen)
                    .frame(width: 22, height: 22)
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Tag Summary

private struct WatchTagSummary: View {
    let tags: [Tag]

    var body: some View {
        HStack(spacing: ShopTheme.spacingXS) {
            ForEach(tags.prefix(3), id: \.id) { tag in
                HStack(spacing: 2) {
                    Circle()
                        .fill(tag.displayColor)
                        .frame(width: 5, height: 5)
                    Text(tag.name)
                        .font(.caption2)
                        .foregroundStyle(tag.displayColor)
                        .lineLimit(1)
                }
            }
            if tags.count > 3 {
                Text("+\(tags.count - 3)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
