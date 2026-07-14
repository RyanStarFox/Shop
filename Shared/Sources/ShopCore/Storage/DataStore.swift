import Foundation
import SwiftData
import Combine

@MainActor
public final class DataStore: ObservableObject {
    public let modelContainer: ModelContainer
    public let modelContext: ModelContext

    @Published public var items: [ShoppingItem] = []
    @Published public var tags: [Tag] = []
    @Published public var selectedFilter: FilterOption = .all
    @Published public var selectedTags: Set<UUID> = []
    @Published public var dateRange: ClosedRange<Date>?

    public enum FilterOption: String, CaseIterable {
        case all
        case active
        case completed
        case today
        case week
        case month
    }

    public init(inMemory: Bool = false) {
        let schema = Schema([ShoppingItem.self, Tag.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [config])
            modelContext = modelContainer.mainContext
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        fetchData()
    }

    public func fetchData() {
        do {
            let itemDescriptor = FetchDescriptor<ShoppingItem>(
                sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt, order: .reverse)]
            )
            items = try modelContext.fetch(itemDescriptor)

            let tagDescriptor = FetchDescriptor<Tag>(
                sortBy: [SortDescriptor(\.name)]
            )
            tags = try modelContext.fetch(tagDescriptor)
        } catch {
            print("Fetch failed: \(error)")
        }
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
        let maxOrder = items.map(\.sortOrder).max() ?? -1
        let item = ShoppingItem(name: name, createdAt: Date(), sortOrder: maxOrder + 1, tags: tags)
        modelContext.insert(item)
        save()
    }

    public func toggleItem(_ item: ShoppingItem) {
        item.isCompleted.toggle()
        item.completedAt = item.isCompleted ? Date() : nil
        save()
    }

    public func deleteItem(_ item: ShoppingItem) {
        modelContext.delete(item)
        save()
    }

    public func updateItem(_ item: ShoppingItem, name: String? = nil, tags: [Tag]? = nil) {
        if let name = name { item.name = name }
        if let tags = tags { item.tags = tags }
        save()
    }

    public func moveItems(from source: IndexSet, to destination: Int) {
        var mutable = items
        mutable.move(fromOffsets: source, toOffset: destination)
        for (index, item) in mutable.enumerated() {
            item.sortOrder = index
        }
        save()
    }

    // MARK: - Tag operations

    public func addTag(name: String, colorHex: String = "#007AFF") {
        let tag = Tag(name: name, colorHex: colorHex)
        modelContext.insert(tag)
        save()
    }

    public func deleteTag(_ tag: Tag) {
        modelContext.delete(tag)
        save()
    }

    public func updateTag(_ tag: Tag, name: String? = nil, colorHex: String? = nil) {
        if let name = name { tag.name = name }
        if let colorHex = colorHex { tag.colorHex = colorHex }
        save()
    }

    // MARK: - Sync support

    public func importItems(_ importedItems: [ShoppingItem]) {
        for imported in importedItems {
            if !items.contains(where: { $0.id == imported.id }) {
                modelContext.insert(imported)
            }
        }
        save()
    }

    public func importTags(_ importedTags: [Tag]) {
        for imported in importedTags {
            if !tags.contains(where: { $0.id == imported.id }) {
                modelContext.insert(imported)
            }
        }
        save()
    }

    public func exportData() -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let export = ExportData(items: items.map(ExportItem.init), tags: tags.map(ExportTag.init))
        return try? encoder.encode(export)
    }

    public func importData(_ data: Data) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let export = try? decoder.decode(ExportData.self, from: data) else { return }

        let importedTags = export.tags.map { $0.toTag() }
        importTags(importedTags)

        let importedItems = export.items.map { exportItem -> ShoppingItem in
            let item = exportItem.toItem()
            let tagIds = Set(exportItem.tagIds)
            item.tags = importedTags.filter { tagIds.contains($0.id) }
            return item
        }
        importItems(importedItems)
    }

    private func save() {
        try? modelContext.save()
        fetchData()
    }
}

// MARK: - Export/Import DTOs

struct ExportData: Codable {
    let items: [ExportItem]
    let tags: [ExportTag]
}

struct ExportItem: Codable {
    let id: UUID
    let name: String
    let isCompleted: Bool
    let createdAt: Date
    let completedAt: Date?
    let sortOrder: Int
    let tagIds: [UUID]

    init(from item: ShoppingItem) {
        self.id = item.id
        self.name = item.name
        self.isCompleted = item.isCompleted
        self.createdAt = item.createdAt
        self.completedAt = item.completedAt
        self.sortOrder = item.sortOrder
        self.tagIds = item.tags.map(\.id)
    }

    func toItem() -> ShoppingItem {
        ShoppingItem(
            id: id, name: name, isCompleted: isCompleted,
            createdAt: createdAt, completedAt: completedAt,
            sortOrder: sortOrder, tags: []
        )
    }
}

struct ExportTag: Codable {
    let id: UUID
    let name: String
    let colorHex: String
    let createdAt: Date

    init(from tag: Tag) {
        self.id = tag.id
        self.name = tag.name
        self.colorHex = tag.colorHex
        self.createdAt = tag.createdAt
    }

    func toTag() -> Tag {
        Tag(id: id, name: name, colorHex: colorHex, createdAt: createdAt)
    }
}
