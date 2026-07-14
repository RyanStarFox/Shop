import Foundation
import SwiftData
import Combine

@MainActor
public final class DataStore: ObservableObject {
    public let modelContainer: ModelContainer
    public let modelContext: ModelContext
    public let shoppingStore: ShoppingStore

    @Published public var items: [ShoppingItem] = []
    @Published public var activeItems: [ShoppingItem] = []
    @Published public var archivedItems: [ShoppingItem] = []
    @Published public var tags: [Tag] = []
    @Published public var lastError: ShoppingStoreError?
    @Published public var selectedFilter: FilterOption = .all
    @Published public var selectedTags: Set<UUID> = []
    @Published public var dateRange: ClosedRange<Date>?
    var onSuccessfulLocalMutation: (() -> Void)?

    public enum FilterOption: String, CaseIterable {
        case all
        case active
        case completed
        case today
        case week
        case month
    }

    public init(inMemory: Bool = false, deviceID: String? = nil) {
        do {
            shoppingStore = try ShoppingStore(
                inMemory: inMemory,
                deviceID: deviceID ?? Self.stableDeviceID()
            )
        } catch {
            fatalError("Failed to create ShoppingStore: \(error)")
        }
        modelContainer = shoppingStore.modelContainer
        modelContext = shoppingStore.modelContext
        fetchData()
    }

    public func fetchData() {
        activeItems = shoppingStore.activeItems
        archivedItems = shoppingStore.archivedItems
        items = activeItems + archivedItems
        tags = shoppingStore.tags
    }

    public var filteredItems: [ShoppingItem] {
        var result = items

        switch selectedFilter {
        case .all:
            break
        case .active:
            result = result.filter { !$0.isCompleted }
        case .completed:
            result = result.filter { $0.isCompleted }
        case .today:
            let today = Calendar.current.startOfDay(for: Date())
            result = result.filter { $0.createdAt >= today }
        case .week:
            if let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) {
                result = result.filter { $0.createdAt >= weekAgo }
            }
        case .month:
            if let monthAgo = Calendar.current.date(byAdding: .month, value: -1, to: Date()) {
                result = result.filter { $0.createdAt >= monthAgo }
            }
        }

        if !selectedTags.isEmpty {
            result = result.filter { item in
                !selectedTags.isDisjoint(with: Set(item.tags.map(\.id)))
            }
        }

        if let range = dateRange {
            result = result.filter { range.contains($0.createdAt) }
        }

        return result
    }

    // MARK: - Item operations

    public func addItem(name: String, tags: [Tag] = []) {
        performMutation {
            _ = try shoppingStore.addItem(name: name, tagIDs: tags.map(\.id))
        }
    }

    public func toggleItem(_ item: ShoppingItem) {
        performMutation {
            try shoppingStore.setCompleted(
                itemID: item.id,
                completed: !item.isCompleted
            )
        }
    }

    public func deleteItem(_ item: ShoppingItem) {
        performMutation {
            try shoppingStore.softDeleteItem(itemID: item.id)
        }
    }

    public func updateItem(_ item: ShoppingItem, name: String? = nil, tags: [Tag]? = nil) {
        performMutation {
            try shoppingStore.updateItem(
                itemID: item.id,
                name: name,
                tagIDs: tags?.map(\.id)
            )
        }
    }

    public func moveItems(from source: IndexSet, to destination: Int) {
        guard selectedFilter == .active,
              selectedTags.isEmpty,
              dateRange == nil else {
            return
        }
        performMutation {
            try shoppingStore.moveActiveItems(from: source, to: destination)
        }
    }

    // MARK: - Tag operations

    public func addTag(name: String, colorHex: String = "#007AFF") {
        performMutation {
            _ = try shoppingStore.addTag(name: name, colorHex: colorHex)
        }
    }

    public func deleteTag(_ tag: Tag) {
        performMutation {
            try shoppingStore.deleteTag(id: tag.id)
        }
    }

    public func updateTag(_ tag: Tag, name: String? = nil, colorHex: String? = nil) {
        performMutation {
            try shoppingStore.updateTag(
                id: tag.id,
                name: name,
                colorHex: colorHex
            )
        }
    }

    // MARK: - Sync support

    public func importItems(_ importedItems: [ShoppingItem]) {
        let snapshot = ExportData(
            items: importedItems.map(ExportItem.init),
            tags: []
        )
        performMutation {
            try shoppingStore.apply(snapshot: snapshot)
        }
    }

    public func importTags(_ importedTags: [Tag]) {
        let snapshot = ExportData(
            items: [],
            tags: importedTags.map(ExportTag.init)
        )
        performMutation {
            try shoppingStore.apply(snapshot: snapshot)
        }
    }

    public func exportData() -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            return try encoder.encode(shoppingStore.makeSnapshot())
        } catch {
            return nil
        }
    }

    public func importData(_ data: Data) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let snapshot = try decoder.decode(SyncSnapshot.self, from: data)
            performMutation {
                try shoppingStore.apply(snapshot: snapshot)
            }
        } catch {
            lastError = .fetchFailed(error.localizedDescription)
        }
    }

    private func performMutation(_ mutation: () throws -> Void) {
        do {
            try mutation()
            lastError = nil
            onSuccessfulLocalMutation?()
        } catch let error as ShoppingStoreError {
            lastError = error
        } catch {
            lastError = .saveFailed(error.localizedDescription)
        }
        fetchData()
    }

    private static func stableDeviceID() -> String {
        let key = "shop.device-id"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: key)
        return generated
    }
}

// MARK: - Export/Import DTOs

public struct ExportData: Codable {
    public let items: [ExportItem]
    public let tags: [ExportTag]

    public init(items: [ExportItem], tags: [ExportTag]) {
        self.items = items
        self.tags = tags
    }
}

public struct ExportItem: Codable {
    public let id: UUID
    public let name: String
    public let isCompleted: Bool
    public let createdAt: Date
    public let completedAt: Date?
    public let sortOrder: Int
    public let tagIds: [UUID]
    public let updatedAt: Date?
    public let deletedAt: Date?
    public let lastEditorDeviceID: String?

    public init(
        id: UUID,
        name: String,
        isCompleted: Bool,
        createdAt: Date,
        completedAt: Date?,
        sortOrder: Int,
        tagIds: [UUID],
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
        lastEditorDeviceID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.sortOrder = sortOrder
        self.tagIds = tagIds
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.lastEditorDeviceID = lastEditorDeviceID
    }

    init(from item: ShoppingItem) {
        self.id = item.id
        self.name = item.name
        self.isCompleted = item.isCompleted
        self.createdAt = item.createdAt
        self.completedAt = item.completedAt
        self.sortOrder = item.sortOrder
        self.tagIds = item.tags.map(\.id)
        self.updatedAt = item.updatedAt
        self.deletedAt = item.deletedAt
        self.lastEditorDeviceID = item.lastEditorDeviceID
    }

    func toItem() -> ShoppingItem {
        ShoppingItem(
            id: id, name: name, isCompleted: isCompleted,
            createdAt: createdAt, completedAt: completedAt,
            sortOrder: sortOrder, updatedAt: updatedAt,
            deletedAt: deletedAt,
            lastEditorDeviceID: lastEditorDeviceID ?? "",
            tags: []
        )
    }
}

public struct ExportTag: Codable {
    public let id: UUID
    public let name: String
    public let colorHex: String
    public let createdAt: Date
    public let updatedAt: Date?
    public let deletedAt: Date?
    public let lastEditorDeviceID: String?

    public init(
        id: UUID,
        name: String,
        colorHex: String,
        createdAt: Date,
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
        lastEditorDeviceID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.lastEditorDeviceID = lastEditorDeviceID
    }

    init(from tag: Tag) {
        self.id = tag.id
        self.name = tag.name
        self.colorHex = tag.colorHex
        self.createdAt = tag.createdAt
        self.updatedAt = tag.updatedAt
        self.deletedAt = tag.deletedAt
        self.lastEditorDeviceID = tag.lastEditorDeviceID
    }

    func toTag() -> Tag {
        Tag(
            id: id,
            name: name,
            colorHex: colorHex,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            lastEditorDeviceID: lastEditorDeviceID ?? ""
        )
    }
}
