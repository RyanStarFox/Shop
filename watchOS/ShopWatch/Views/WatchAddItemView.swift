import SwiftUI
import ShopCore

struct WatchAddItemView: View {
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) var dismiss

    @State private var itemName = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    TextField(ShopStrings.itemName, text: $itemName)
                        .focused($isFocused)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.ultraThinMaterial)
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
                    .tint(.accentColor)
                    .disabled(itemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
            }
            .navigationTitle(ShopStrings.addItem)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            isFocused = true
        }
    }

    private func addItem() {
        let name = itemName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        dataStore.addItem(name: name)
        dismiss()
    }
}
