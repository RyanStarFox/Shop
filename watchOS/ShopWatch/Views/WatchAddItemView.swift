import SwiftUI
import WatchKit
import ShopCore

struct WatchAddItemView: View {
    @EnvironmentObject private var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var itemName = ""
    @State private var selectedTagIDs: Set<UUID> = []
    @FocusState private var isFocused: Bool

    private var trimmedName: String {
        itemName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAdd: Bool {
        !trimmedName.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ShopTheme.spacingMD) {
                    TextField(ShopStrings.itemName, text: $itemName)
                        .focused($isFocused)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, ShopTheme.spacingSM + 4)
                        .padding(.vertical, ShopTheme.spacingSM + 2)
                        .background {
                            RoundedRectangle(cornerRadius: ShopTheme.rowCornerRadius, style: .continuous)
                                .fill(.ultraThinMaterial)
                        }
                        .accessibilityLabel(ShopStrings.itemName)

                    if !dataStore.tags.isEmpty {
                        tagSelectionSection
                    }

                    Button {
                        addItem()
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text(ShopStrings.addItem)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .tint(ShopTheme.naturalGreen)
                    .disabled(!canAdd)
                    .accessibilityLabel(ShopStrings.addItem)
                }
                .padding()
            }
            .navigationTitle(ShopStrings.addItem)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(WatchStrings.cancel) {
                        dismiss()
                    }
                    .accessibilityLabel(WatchStrings.cancel)
                }
            }
        }
        .onAppear {
            isFocused = true
        }
    }

    @ViewBuilder
    private var tagSelectionSection: some View {
        VStack(alignment: .leading, spacing: ShopTheme.spacingSM) {
            Text(ShopStrings.tags)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: ShopTheme.spacingXS) {
                ForEach(dataStore.tags) { tag in
                    Button {
                        toggleTag(tag.id)
                    } label: {
                        HStack(spacing: ShopTheme.spacingSM) {
                            Circle()
                                .fill(tag.displayColor)
                                .frame(width: 8, height: 8)

                            Text(tag.name)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Spacer(minLength: 0)

                            if selectedTagIDs.contains(tag.id) {
                                Image(systemName: "checkmark")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(ShopTheme.naturalGreen)
                            }
                        }
                        .frame(minHeight: ShopTheme.minTouchTarget)
                        .padding(.horizontal, ShopTheme.spacingSM)
                        .background {
                            RoundedRectangle(cornerRadius: ShopTheme.rowCornerRadius, style: .continuous)
                                .fill(
                                    selectedTagIDs.contains(tag.id)
                                        ? tag.displayColor.opacity(0.15)
                                        : Color.clear
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(
                        selectedTagIDs.contains(tag.id) ? .isSelected : []
                    )
                    .accessibilityLabel(tag.name)
                }
            }
        }
    }

    private func toggleTag(_ tagID: UUID) {
        if selectedTagIDs.contains(tagID) {
            selectedTagIDs.remove(tagID)
        } else {
            selectedTagIDs.insert(tagID)
        }
    }

    private func addItem() {
        guard canAdd else { return }
        let selectedTags = dataStore.tags.filter { selectedTagIDs.contains($0.id) }
        dataStore.addItem(name: trimmedName, tags: selectedTags)
        WKInterfaceDevice.current().play(.success)
        dismiss()
    }
}
