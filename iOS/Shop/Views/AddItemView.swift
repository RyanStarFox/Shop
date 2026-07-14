import SwiftUI
import ShopCore

struct AddItemView: View {
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) var dismiss

    @State private var itemName = ""
    @State private var selectedTags: Set<UUID> = []
    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassBackground()

                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 6) {
                        Image(systemName: "cart.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.accentColor.gradient)

                        Text(ShopStrings.addItem)
                            .font(.title2.weight(.bold))
                        Text(ShopStrings.relativeTime(from: Date()))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 20)

                    // Name input
                    GlassTextField(
                        placeholder: ShopStrings.itemName,
                        text: $itemName,
                        systemImage: "pencil"
                    )
                    .focused($isNameFocused)
                    .padding(.horizontal)

                    // Tag selection
                    if !dataStore.tags.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(ShopStrings.tags)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)

                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 80), spacing: 8)],
                                spacing: 8
                            ) {
                                ForEach(dataStore.tags) { tag in
                                    TagChip(
                                        tag: tag,
                                        isSelected: selectedTags.contains(tag.id),
                                        onTap: {
                                            if selectedTags.contains(tag.id) {
                                                selectedTags.remove(tag.id)
                                            } else {
                                                selectedTags.insert(tag.id)
                                            }
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    Spacer()

                    // Add button
                    GlassButton(
                        ShopStrings.addItem,
                        systemImage: "plus",
                        isFullWidth: true
                    ) {
                        addItem()
                    }
                    .disabled(itemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(itemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
                    .padding(.horizontal)
                    .padding(.bottom, 30)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear {
            isNameFocused = true
        }
    }

    private func addItem() {
        let name = itemName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let tags = dataStore.tags.filter { selectedTags.contains($0.id) }
        dataStore.addItem(name: name, tags: tags)
        dismiss()
    }
}
