import SwiftUI
import WatchKit
import ShopCore

struct WatchEditItemView: View {
    let itemID: UUID

    @EnvironmentObject private var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var createdAt = Date()
    @State private var completedAt = Date()

    private var item: ShoppingItem? {
        dataStore.items.first { $0.id == itemID }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let item {
                    Form {
                        Section {
                            Text(item.name)
                                .font(.body.weight(.semibold))
                        }

                        Section {
                            DatePicker(
                                ShopStrings.addedAt,
                                selection: $createdAt,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            if item.isCompleted {
                                DatePicker(
                                    ShopStrings.completedAtLabel,
                                    selection: $completedAt,
                                    displayedComponents: [.date, .hourAndMinute]
                                )
                            }
                        }

                        Section {
                            Button(ShopStrings.saveItem) {
                                save(item)
                            }
                        }
                    }
                    .onAppear {
                        createdAt = item.createdAt
                        completedAt = item.completedAt ?? item.createdAt
                    }
                } else {
                    Text(ShopStrings.editItem)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(ShopStrings.editItem)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(WatchStrings.cancel) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func save(_ item: ShoppingItem) {
        dataStore.updateItem(
            item,
            createdAt: createdAt,
            completedAt: item.isCompleted ? completedAt : nil,
            updateCompletedAt: item.isCompleted
        )
        WKInterfaceDevice.current().play(.click)
        dismiss()
    }
}
