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
    @State private var createdAt = Date()
    @State private var completedAt = Date()
    @State private var showDiscardConfirmation = false
    @State private var newTagName = ""
    @State private var newTagColor = "#E0312C"
    @FocusState private var isNameFocused: Bool
    @FocusState private var isNewTagFocused: Bool

    private let presetColors: [(String, Color)] = [
        ("#007AFF", .blue),
        ("#34C759", .green),
        ("#FF9500", .orange),
        ("#FF3B30", .red),
        ("#AF52DE", .purple),
        ("#FF2D55", .pink),
        ("#5856D6", .indigo),
        ("#00C7BE", .teal),
        ("#FFD60A", .yellow),
        ("#8E8E93", .gray)
    ]

    private var editingItem: ShoppingItem? {
        if case .edit(let item) = mode { return item }
        return nil
    }

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
            let createdChanged = !Calendar.current.isDate(createdAt, equalTo: item.createdAt, toGranularity: .minute)
            let completedChanged: Bool
            if item.isCompleted {
                completedChanged = !Calendar.current.isDate(
                    completedAt,
                    equalTo: item.completedAt ?? item.createdAt,
                    toGranularity: .minute
                )
            } else {
                completedChanged = false
            }
            return trimmedName != item.name
                || selectedTags != originalTags
                || createdChanged
                || completedChanged
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

    private var datesSummary: String {
        var parts = ["\(ShopStrings.addedAt) \(createdAt.formatted(date: .abbreviated, time: .omitted))"]
        if editingItem?.isCompleted == true {
            parts.append(
                "\(ShopStrings.completedAtLabel) \(completedAt.formatted(date: .abbreviated, time: .omitted))"
            )
        }
        return parts.joined(separator: " · ")
    }

    private var canAddTag: Bool {
        !newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                                Spacer(minLength: 0)
                                if selectedTags.contains(tag.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(ShopTheme.brandRed)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: ShopTheme.minTouchTarget, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(
                            selectedTags.contains(tag.id) ? .isSelected : []
                        )
                        .accessibilityLabel(tag.name)
                    }

                    VStack(alignment: .leading, spacing: ShopTheme.spacingSM) {
                        TextField(ShopStrings.tagName, text: $newTagName)
                            .focused($isNewTagFocused)
                            .textInputAutocapitalization(.words)
                            .accessibilityLabel(ShopStrings.tagName)

                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5),
                            spacing: 10
                        ) {
                            ForEach(presetColors.dropLast(), id: \.0) { hex, color in
                                Button {
                                    newTagColor = hex
                                } label: {
                                    Circle()
                                        .fill(color.gradient)
                                        .frame(width: 32, height: 32)
                                        .overlay {
                                            if newTagColor == hex {
                                                Circle()
                                                    .stroke(.primary, lineWidth: 2)
                                                    .frame(width: 36, height: 36)
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(hex)
                            }

                            ColorPicker(
                                selection: customColorBinding(for: $newTagColor),
                                supportsOpacity: false
                            ) {
                                EmptyView()
                            }
                            .labelsHidden()
                            .frame(width: 32, height: 32)
                            .overlay {
                                Circle()
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [3]))
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityLabel(ShopStrings.customColor)
                        }

                        Button {
                            addNewTag()
                        } label: {
                            Label(ShopStrings.addTag, systemImage: "plus.tag")
                                .frame(maxWidth: .infinity, minHeight: ShopTheme.minTouchTarget)
                        }
                        .disabled(!canAddTag)
                    }
                    .padding(.vertical, ShopTheme.spacingXS)
                }

                if case .edit = mode {
                    Section {
                        DisclosureGroup {
                            DatePicker(
                                ShopStrings.addedAt,
                                selection: $createdAt,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            if editingItem?.isCompleted == true {
                                DatePicker(
                                    ShopStrings.completedAtLabel,
                                    selection: $completedAt,
                                    displayedComponents: [.date, .hourAndMinute]
                                )
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ShopStrings.datesSection)
                                Text(datesSummary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
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
        .tint(ShopTheme.brandRed)
    }

    private func loadInitialState() {
        switch mode {
        case .add:
            createdAt = Date()
            completedAt = Date()
            isNameFocused = true
        case .edit(let item):
            itemName = item.name
            selectedTags = Set(item.tags.map(\.id))
            createdAt = item.createdAt
            completedAt = item.completedAt ?? item.createdAt
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

    private func addNewTag() {
        let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        dataStore.addTag(name: name, colorHex: newTagColor)
        if let created = dataStore.tags.first(where: { $0.name == name }) {
            selectedTags.insert(created.id)
        }
        newTagName = ""
        newTagColor = "#E0312C"
        isNewTagFocused = false
    }

    private func customColorBinding(for hex: Binding<String>) -> Binding<Color> {
        Binding(
            get: { Color(shopHex: hex.wrappedValue) ?? ShopTheme.brandRed },
            set: { color in
                if let value = color.shopHexString {
                    hex.wrappedValue = value
                }
            }
        )
    }

    private func save() {
        guard canSave else { return }
        let tags = dataStore.tags.filter { selectedTags.contains($0.id) }

        switch mode {
        case .add:
            dataStore.addItem(name: trimmedName, tags: tags)
        case .edit(let item):
            dataStore.updateItem(
                item,
                name: trimmedName,
                tags: tags,
                createdAt: createdAt,
                completedAt: item.isCompleted ? completedAt : nil,
                updateCompletedAt: item.isCompleted
            )
        }

        dismiss()
    }
}
