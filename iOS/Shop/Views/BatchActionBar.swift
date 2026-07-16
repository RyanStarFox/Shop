import SwiftUI
import ShopCore

struct BatchActionBar: View {
    let selectedCount: Int
    let onComplete: () -> Void
    let onRestore: () -> Void
    let onTags: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: ShopTheme.spacingSM) {
            Text(ShopStrings.selectionCount(selectedCount))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: ShopTheme.spacingSM) {
                batchButton(
                    title: ShopStrings.selectionMarkAllComplete,
                    systemImage: "checkmark.circle",
                    action: onComplete
                )
                .disabled(selectedCount == 0)

                batchButton(
                    title: ShopStrings.selectionMarkAllIncomplete,
                    systemImage: "arrow.uturn.backward.circle",
                    action: onRestore
                )
                .disabled(selectedCount == 0)

                batchButton(
                    title: ShopStrings.selectionEditTags,
                    systemImage: "tag",
                    action: onTags
                )
                .disabled(selectedCount == 0)

                batchButton(
                    title: ShopStrings.deleteItem,
                    systemImage: "trash",
                    role: .destructive,
                    action: onDelete
                )
                .disabled(selectedCount == 0)
            }
        }
        .padding(.horizontal, ShopTheme.spacingMD)
        .padding(.vertical, ShopTheme.spacingSM)
        .background(.ultraThinMaterial)
    }

    private func batchButton(
        title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                Text(title)
                    .font(.caption2)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: ShopTheme.minTouchTarget)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(ShopStrings.selectionCount(selectedCount))")
    }
}

struct BatchTagEditorView: View {
    let selectedItemIDs: Set<UUID>
    @EnvironmentObject private var dataStore: DataStore
    @EnvironmentObject private var undoCoordinator: UndoCoordinator
    @Environment(\.dismiss) private var dismiss

    private var selectedItems: [ShoppingItem] {
        dataStore.items.filter { selectedItemIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
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
                    }
                    .accessibilityLabel(tag.name)
                    .accessibilityValue(accessibility(for: membership))
                }
            }
            .navigationTitle(ShopStrings.selectionEditTags)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ShopStrings.selectionDone) { dismiss() }
                }
            }
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
