import SwiftUI
import ShopCore

struct TagManagementView: View {
    @EnvironmentObject var dataStore: DataStore
    @EnvironmentObject var undoCoordinator: UndoCoordinator
    @Environment(\.dismiss) var dismiss

    @State private var newTagName = ""
    @State private var newTagColor = "#007AFF"
    @State private var editingTag: Tag? = nil
    @State private var editingName = ""
    @State private var editingColor = ""
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

    var body: some View {
        NavigationStack {
            ZStack {
                ShopSurfaceBackground()

                ScrollView {
                    VStack(spacing: 20) {
                        // Add new tag
                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Label(ShopStrings.addTag, systemImage: "plus.tag")
                                    .font(.headline)

                                GlassTextField(
                                    placeholder: ShopStrings.tagName,
                                    text: $newTagName,
                                    systemImage: "tag"
                                )
                                .focused($isNewTagFocused)

                                // Color picker
                                Text(ShopStrings.tagColor)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                LazyVGrid(
                                    columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5),
                                    spacing: 10
                                ) {
                                    ForEach(presetColors, id: \.0) { hex, color in
                                        Button {
                                            newTagColor = hex
                                        } label: {
                                            Circle()
                                                .fill(color.gradient)
                                                .frame(width: 40, height: 40)
                                                .overlay {
                                                    if newTagColor == hex {
                                                        Circle()
                                                            .stroke(.white, lineWidth: 3)
                                                            .frame(width: 44, height: 44)
                                                    }
                                                }
                                                .shadow(color: color.opacity(0.4), radius: 4)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }

                                GlassButton(
                                    ShopStrings.addTag,
                                    systemImage: "plus",
                                    isFullWidth: true
                                ) {
                                    addTag()
                                }
                                .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                        .padding(.horizontal)

                        // Existing tags
                        if !dataStore.tags.isEmpty {
                            GlassCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    Label(ShopStrings.manageTags, systemImage: "list.bullet.tag")
                                        .font(.headline)

                                    ForEach(dataStore.tags) { tag in
                                        TagEditRow(tag: tag) {
                                            dataStore.deleteTag(tag, presentUndo: undoCoordinator.present)
                                        } onRename: { newName in
                                            dataStore.updateTag(tag, name: newName)
                                        } onColorChange: { newColor in
                                            dataStore.updateTag(tag, colorHex: newColor)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                        } else {
                            GlassCard {
                                VStack(spacing: 8) {
                                    Image(systemName: "tag.slash")
                                        .font(.system(size: 30))
                                        .foregroundStyle(.secondary)
                                    Text(ShopStrings.noTags)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle(ShopStrings.manageTags)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func addTag() {
        let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        dataStore.addTag(name: name, colorHex: newTagColor)
        newTagName = ""
        newTagColor = "#007AFF"
    }
}

// MARK: - Tag Edit Row

struct TagEditRow: View {
    let tag: Tag
    var onDelete: () -> Void
    var onRename: (String) -> Void
    var onColorChange: (String) -> Void

    @State private var isEditing = false
    @State private var editName: String

    private let presetColors: [(String, Color)] = [
        ("#007AFF", .blue), ("#34C759", .green), ("#FF9500", .orange),
        ("#FF3B30", .red), ("#AF52DE", .purple), ("#FF2D55", .pink),
        ("#5856D6", .indigo), ("#00C7BE", .teal), ("#FFD60A", .yellow), ("#8E8E93", .gray)
    ]

    init(tag: Tag, onDelete: @escaping () -> Void, onRename: @escaping (String) -> Void, onColorChange: @escaping (String) -> Void) {
        self.tag = tag
        self.onDelete = onDelete
        self.onRename = onRename
        self.onColorChange = onColorChange
        _editName = State(initialValue: tag.name)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Circle()
                    .fill(tag.displayColor.gradient)
                    .frame(width: 28, height: 28)
                    .shadow(color: tag.displayColor.opacity(0.4), radius: 4)

                if isEditing {
                    TextField("Name", text: $editName)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            onRename(editName)
                            isEditing = false
                        }
                } else {
                    Text(tag.name)
                        .font(.body.weight(.medium))
                }

                Spacer()

                Button {
                    if isEditing {
                        onRename(editName)
                    }
                    isEditing.toggle()
                } label: {
                    Image(systemName: isEditing ? "checkmark.circle.fill" : "pencil.circle")
                        .foregroundStyle(isEditing ? .green : .secondary)
                }
                .buttonStyle(.plain)

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash.circle")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .frame(minWidth: ShopTheme.minTouchTarget, minHeight: ShopTheme.minTouchTarget)
                .accessibilityLabel(ShopStrings.deleteItem)
            }

            if isEditing {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5),
                    spacing: 6
                ) {
                    ForEach(presetColors, id: \.0) { hex, color in
                        Button {
                            onColorChange(hex)
                        } label: {
                            Circle()
                                .fill(color.gradient)
                                .frame(width: 28, height: 28)
                                .overlay {
                                    if tag.colorHex == hex {
                                        Circle()
                                            .stroke(.white, lineWidth: 2)
                                            .frame(width: 32, height: 32)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
