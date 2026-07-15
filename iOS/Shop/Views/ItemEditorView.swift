import SwiftUI
import ShopCore

struct ItemEditorView: View {
    enum Mode: Equatable {
        case add
        case edit(ShoppingItem)
    }

    let mode: Mode

    @EnvironmentObject private var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var itemName = ""
    @State private var selectedTags: Set<UUID> = []
    @State private var showDiscardConfirmation = false
    @FocusState private var isNameFocused: Bool

    private var trimmedName: String {
        itemName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty
    }

    private var hasUnsavedChanges: Bool {
        switch mode {
        case .add:
            return !trimmedName.isEmpty || !selectedTags.isEmpty
        case .edit(let item):
            let originalTags = Set(item.tags.map(\.id))
            return trimmedName != item.name || selectedTags != originalTags
        }
    }

    private var navigationTitle: String {
        switch mode {
        case .add:
            ShopStrings.addItem
        case .edit:
            ShopStrings.editItem
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(ShopStrings.itemName, text: $itemName)
                        .focused($isNameFocused)
                        .textInputAutocapitalization(.sentences)
                        .accessibilityLabel(ShopStrings.itemName)
                }

                if !dataStore.tags.isEmpty {
                    Section(ShopStrings.tags) {
                        ForEach(dataStore.tags) { tag in
                            Button {
                                toggleTag(tag.id)
                            } label: {
                                HStack(spacing: ShopTheme.spacingSM) {
                                    Circle()
                                        .fill(tag.displayColor)
                                        .frame(width: 10, height: 10)
                                    Text(tag.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if selectedTags.contains(tag.id) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(ShopTheme.naturalGreen)
                                    }
                                }
                                .frame(minHeight: ShopTheme.minTouchTarget)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(
                                selectedTags.contains(tag.id) ? .isSelected : []
                            )
                            .accessibilityLabel(tag.name)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(ShopSurfaceBackground())
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ShopStrings.discardChanges) {
                        if hasUnsavedChanges {
                            showDiscardConfirmation = true
                        } else {
                            dismiss()
                        }
                    }
                    .accessibilityLabel(ShopStrings.discardChanges)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(ShopStrings.saveItem) {
                        save()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                    .accessibilityLabel(ShopStrings.saveItem)
                }
            }
            .interactiveDismissDisabled(hasUnsavedChanges)
            .confirmationDialog(
                ShopStrings.discardChanges,
                isPresented: $showDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button(ShopStrings.discardChanges, role: .destructive) {
                    dismiss()
                }
                Button(ShopStrings.saveItem) {
                    save()
                }
            }
            .onAppear(perform: loadInitialState)
        }
        .tint(ShopTheme.naturalGreen)
    }

    private func loadInitialState() {
        switch mode {
        case .add:
            isNameFocused = true
        case .edit(let item):
            itemName = item.name
            selectedTags = Set(item.tags.map(\.id))
            isNameFocused = true
        }
    }

    private func toggleTag(_ id: UUID) {
        if selectedTags.contains(id) {
            selectedTags.remove(id)
        } else {
            selectedTags.insert(id)
        }
    }

    private func save() {
        guard canSave else { return }
        let tags = dataStore.tags.filter { selectedTags.contains($0.id) }

        switch mode {
        case .add:
            dataStore.addItem(name: trimmedName, tags: tags)
        case .edit(let item):
            dataStore.updateItem(item, name: trimmedName, tags: tags)
        }

        dismiss()
    }
}
