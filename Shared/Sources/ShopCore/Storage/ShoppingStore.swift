import Foundation
import SwiftData

public enum ShoppingStoreError: Error, Equatable, LocalizedError {
    case containerCreationFailed(String)
    case fetchFailed(String)
    case saveFailed(String)
    case itemNotFound(UUID)
    case tagNotFound(UUID)

    public var errorDescription: String? {
        switch self {
        case .containerCreationFailed(let message):
            ShopStrings.shoppingStoreContainerCreationFailed(message)
        case .fetchFailed(let message):
            ShopStrings.shoppingStoreFetchFailed(message)
        case .saveFailed(let message):
            ShopStrings.shoppingStoreSaveFailed(message)
        case .itemNotFound(let id):
            ShopStrings.shoppingStoreItemNotFound(id)
        case .tagNotFound(let id):
            ShopStrings.shoppingStoreTagNotFound(id)
        }
    }
}

@MainActor
public final class ShoppingStore {
    private static let currentRecordSchemaVersion = 2

    public let modelContainer: ModelContainer
    public let modelContext: ModelContext
    public let deviceID: String

    private var storedItems: [ShoppingItem]
    private var storedTags: [Tag]

    public init(
        inMemory: Bool = false,
        deviceID: String,
        storeURL: URL? = nil
    ) throws {
        self.deviceID = deviceID

        let schema = Schema([ShoppingItem.self, Tag.self])
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        } else if let storeURL {
            configuration = ModelConfiguration(schema: schema, url: storeURL)
        } else {
            configuration = ModelConfiguration(isStoredInMemoryOnly: false)
        }
        do {
            modelContainer = try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
        } catch {
            throw ShoppingStoreError.containerCreationFailed(error.localizedDescription)
        }
        modelContext = modelContainer.mainContext

        do {
            storedItems = try modelContext.fetch(FetchDescriptor<ShoppingItem>())
            storedTags = try modelContext.fetch(FetchDescriptor<Tag>())
        } catch {
            throw ShoppingStoreError.fetchFailed(error.localizedDescription)
        }

        try backfillLegacyVersions()
    }

    public var items: [ShoppingItem] {
        sortedItems(storedItems.filter { $0.deletedAt == nil })
    }

    public var allItems: [ShoppingItem] {
        sortedItems(storedItems)
    }

    public var activeItems: [ShoppingItem] {
        sortedItems(storedItems.filter { $0.deletedAt == nil && !$0.isCompleted })
    }

    public var archivedItems: [ShoppingItem] {
        sortedItems(storedItems.filter { $0.deletedAt == nil && $0.isCompleted })
    }

    public var tags: [Tag] {
        storedTags
            .filter { $0.deletedAt == nil }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public var allTags: [Tag] {
        storedTags.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    public func item(id: UUID) -> ShoppingItem? {
        storedItems.first { $0.id == id }
    }

    public func tag(id: UUID) -> Tag? {
        storedTags.first { $0.id == id }
    }

    @discardableResult
    public func addItem(
        name: String,
        tagIDs: [UUID],
        now: Date = Date()
    ) throws -> ShoppingItem {
        let selectedTags = try activeTags(ids: tagIDs)
        let nextOrder = items.map(\.sortOrder).max().map { $0 + 1 } ?? 0
        let item = ShoppingItem(
            name: name,
            createdAt: now,
            sortOrder: nextOrder,
            updatedAt: now,
            lastEditorDeviceID: deviceID,
            tags: selectedTags
        )

        modelContext.insert(item)
        do {
            try save()
            storedItems.append(item)
            return item
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    public func updateItem(
        itemID: UUID,
        name: String? = nil,
        tagIDs: [UUID]? = nil,
        now: Date = Date()
    ) throws {
        guard let item = item(id: itemID) else {
            throw ShoppingStoreError.itemNotFound(itemID)
        }
        let selectedTags = try tagIDs.map(activeTags(ids:))
        let previousName = item.name
        let previousTags = item.tags
        let previousUpdatedAt = item.updatedAt
        let previousDeviceID = item.lastEditorDeviceID

        if let name {
            item.name = name
        }
        if let selectedTags {
            item.tags = selectedTags
        }
        advanceVersion(of: item, now: now)

        do {
            try save()
        } catch {
            item.name = previousName
            item.tags = previousTags
            item.updatedAt = previousUpdatedAt
            item.lastEditorDeviceID = previousDeviceID
            modelContext.rollback()
            throw error
        }
    }

    public func setCompleted(
        itemID: UUID,
        completed: Bool,
        now: Date = Date()
    ) throws {
        guard let item = item(id: itemID) else {
            throw ShoppingStoreError.itemNotFound(itemID)
        }
        let previousCompleted = item.isCompleted
        let previousCompletedAt = item.completedAt
        let previousUpdatedAt = item.updatedAt
        let previousDeviceID = item.lastEditorDeviceID

        item.isCompleted = completed
        item.completedAt = completed ? now : nil
        advanceVersion(of: item, now: now)

        do {
            try save()
        } catch {
            item.isCompleted = previousCompleted
            item.completedAt = previousCompletedAt
            item.updatedAt = previousUpdatedAt
            item.lastEditorDeviceID = previousDeviceID
            modelContext.rollback()
            throw error
        }
    }

    public func softDeleteItem(itemID: UUID, now: Date = Date()) throws {
        guard let item = item(id: itemID) else {
            throw ShoppingStoreError.itemNotFound(itemID)
        }
        let previousDeletedAt = item.deletedAt
        let previousUpdatedAt = item.updatedAt
        let previousDeviceID = item.lastEditorDeviceID

        item.deletedAt = now
        advanceVersion(of: item, now: now)

        do {
            try save()
        } catch {
            item.deletedAt = previousDeletedAt
            item.updatedAt = previousUpdatedAt
            item.lastEditorDeviceID = previousDeviceID
            modelContext.rollback()
            throw error
        }
    }

    public func restoreItem(itemID: UUID, now: Date = Date()) throws {
        guard let item = item(id: itemID) else {
            throw ShoppingStoreError.itemNotFound(itemID)
        }
        let previousDeletedAt = item.deletedAt
        let previousUpdatedAt = item.updatedAt
        let previousDeviceID = item.lastEditorDeviceID

        item.deletedAt = nil
        advanceVersion(of: item, now: now)

        do {
            try save()
        } catch {
            item.deletedAt = previousDeletedAt
            item.updatedAt = previousUpdatedAt
            item.lastEditorDeviceID = previousDeviceID
            modelContext.rollback()
            throw error
        }
    }

    @discardableResult
    public func addTag(
        name: String,
        colorHex: String = "#007AFF",
        now: Date = Date()
    ) throws -> Tag {
        let tag = Tag(
            name: name,
            colorHex: colorHex,
            createdAt: now,
            updatedAt: now,
            lastEditorDeviceID: deviceID
        )
        modelContext.insert(tag)

        do {
            try save()
            storedTags.append(tag)
            return tag
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    public func updateTag(
        id: UUID,
        name: String? = nil,
        colorHex: String? = nil,
        now: Date = Date()
    ) throws {
        guard let tag = tag(id: id) else {
            throw ShoppingStoreError.tagNotFound(id)
        }
        let previousName = tag.name
        let previousColorHex = tag.colorHex
        let previousUpdatedAt = tag.updatedAt
        let previousDeviceID = tag.lastEditorDeviceID

        if let name {
            tag.name = name
        }
        if let colorHex {
            tag.colorHex = colorHex
        }
        advanceVersion(of: tag, now: now)

        do {
            try save()
        } catch {
            tag.name = previousName
            tag.colorHex = previousColorHex
            tag.updatedAt = previousUpdatedAt
            tag.lastEditorDeviceID = previousDeviceID
            modelContext.rollback()
            throw error
        }
    }

    public func deleteTag(id: UUID, now: Date = Date()) throws {
        guard let tag = tag(id: id) else {
            throw ShoppingStoreError.tagNotFound(id)
        }
        let affectedItems = storedItems.filter { item in
            item.tags.contains { $0.id == id }
        }
        let previousTags = affectedItems.map { ($0, $0.tags, $0.updatedAt, $0.lastEditorDeviceID) }
        let previousDeletedAt = tag.deletedAt
        let previousUpdatedAt = tag.updatedAt
        let previousDeviceID = tag.lastEditorDeviceID

        for item in affectedItems {
            item.tags.removeAll { $0.id == id }
            advanceVersion(of: item, now: now)
        }
        tag.deletedAt = now
        advanceVersion(of: tag, now: now)

        do {
            try save()
        } catch {
            for (item, tags, updatedAt, editorDeviceID) in previousTags {
                item.tags = tags
                item.updatedAt = updatedAt
                item.lastEditorDeviceID = editorDeviceID
            }
            tag.deletedAt = previousDeletedAt
            tag.updatedAt = previousUpdatedAt
            tag.lastEditorDeviceID = previousDeviceID
            modelContext.rollback()
            throw error
        }
    }

    public func moveActiveItems(
        from source: IndexSet,
        to destination: Int,
        now: Date = Date()
    ) throws {
        var reordered = activeItems
        reordered.move(fromOffsets: source, toOffset: destination)
        let previousValues = reordered.map { ($0, $0.sortOrder, $0.updatedAt, $0.lastEditorDeviceID) }

        for (index, item) in reordered.enumerated() where item.sortOrder != index {
            item.sortOrder = index
            advanceVersion(of: item, now: now)
        }

        do {
            try save()
        } catch {
            for (item, sortOrder, updatedAt, editorDeviceID) in previousValues {
                item.sortOrder = sortOrder
                item.updatedAt = updatedAt
                item.lastEditorDeviceID = editorDeviceID
            }
            modelContext.rollback()
            throw error
        }
    }

    public func makeSnapshot(now: Date = Date()) throws -> SyncSnapshot {
        SyncSnapshot(
            version: SyncSnapshot.currentVersion,
            generatedAt: now,
            items: allItems
                .map { item in
                    ItemSnapshot(
                        id: item.id,
                        name: item.name,
                        isCompleted: item.isCompleted,
                        createdAt: item.createdAt,
                        completedAt: item.completedAt,
                        updatedAt: item.updatedAt,
                        deletedAt: item.deletedAt,
                        sortOrder: item.sortOrder,
                        tagIDs: item.tags.map(\.id).sorted { $0.uuidString < $1.uuidString },
                        lastEditorDeviceID: item.lastEditorDeviceID
                    )
                }
                .sorted { $0.id.uuidString < $1.id.uuidString },
            tags: allTags
                .map { tag in
                    TagSnapshot(
                        id: tag.id,
                        name: tag.name,
                        colorHex: tag.colorHex,
                        createdAt: tag.createdAt,
                        updatedAt: tag.updatedAt,
                        deletedAt: tag.deletedAt,
                        lastEditorDeviceID: tag.lastEditorDeviceID
                    )
                }
                .sorted { $0.id.uuidString < $1.id.uuidString }
        )
    }

    public func apply(snapshot: SyncSnapshot) throws {
        var insertedTags: [Tag] = []
        for tagSnapshot in snapshot.tags {
            let tag = tag(id: tagSnapshot.id) ?? {
                let newTag = Tag(
                    id: tagSnapshot.id,
                    name: tagSnapshot.name,
                    colorHex: tagSnapshot.colorHex,
                    createdAt: tagSnapshot.createdAt,
                    updatedAt: tagSnapshot.updatedAt,
                    deletedAt: tagSnapshot.deletedAt,
                    lastEditorDeviceID: tagSnapshot.lastEditorDeviceID,
                    recordSchemaVersion: Self.currentRecordSchemaVersion
                )
                modelContext.insert(newTag)
                insertedTags.append(newTag)
                return newTag
            }()
            tag.name = tagSnapshot.name
            tag.colorHex = tagSnapshot.colorHex
            tag.createdAt = tagSnapshot.createdAt
            tag.updatedAt = tagSnapshot.updatedAt
            tag.deletedAt = tagSnapshot.deletedAt
            tag.lastEditorDeviceID = tagSnapshot.lastEditorDeviceID
            tag.recordSchemaVersion = Self.currentRecordSchemaVersion
        }

        let canonicalTags = Dictionary(
            uniqueKeysWithValues: (storedTags + insertedTags).map { ($0.id, $0) }
        )
        var insertedItems: [ShoppingItem] = []
        for itemSnapshot in snapshot.items {
            let item = item(id: itemSnapshot.id) ?? {
                let newItem = ShoppingItem(
                    id: itemSnapshot.id,
                    name: itemSnapshot.name,
                    isCompleted: itemSnapshot.isCompleted,
                    createdAt: itemSnapshot.createdAt,
                    completedAt: itemSnapshot.completedAt,
                    sortOrder: itemSnapshot.sortOrder,
                    updatedAt: itemSnapshot.updatedAt,
                    deletedAt: itemSnapshot.deletedAt,
                    lastEditorDeviceID: itemSnapshot.lastEditorDeviceID,
                    recordSchemaVersion: Self.currentRecordSchemaVersion
                )
                modelContext.insert(newItem)
                insertedItems.append(newItem)
                return newItem
            }()
            item.name = itemSnapshot.name
            item.isCompleted = itemSnapshot.isCompleted
            item.createdAt = itemSnapshot.createdAt
            item.completedAt = itemSnapshot.completedAt
            item.sortOrder = itemSnapshot.sortOrder
            item.updatedAt = itemSnapshot.updatedAt
            item.deletedAt = itemSnapshot.deletedAt
            item.lastEditorDeviceID = itemSnapshot.lastEditorDeviceID
            item.recordSchemaVersion = Self.currentRecordSchemaVersion
            item.tags = Array(Set(itemSnapshot.tagIDs))
                .sorted { $0.uuidString < $1.uuidString }
                .compactMap { id in
                    guard let tag = canonicalTags[id], tag.deletedAt == nil else {
                        return nil
                    }
                    return tag
                }
        }

        do {
            try save()
            storedTags.append(contentsOf: insertedTags)
            storedItems.append(contentsOf: insertedItems)
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    public func apply(snapshot: ExportData) throws {
        let convertedSnapshot = SyncSnapshot(
            version: 1,
            generatedAt: Date(),
            items: snapshot.items.map {
                ItemSnapshot(
                    id: $0.id,
                    name: $0.name,
                    isCompleted: $0.isCompleted,
                    createdAt: $0.createdAt,
                    completedAt: $0.completedAt,
                    updatedAt: $0.updatedAt ?? $0.createdAt,
                    deletedAt: $0.deletedAt,
                    sortOrder: $0.sortOrder,
                    tagIDs: $0.tagIds,
                    lastEditorDeviceID: $0.lastEditorDeviceID ?? "legacy"
                )
            },
            tags: snapshot.tags.map {
                TagSnapshot(
                    id: $0.id,
                    name: $0.name,
                    colorHex: $0.colorHex,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt ?? $0.createdAt,
                    deletedAt: $0.deletedAt,
                    lastEditorDeviceID: $0.lastEditorDeviceID ?? "legacy"
                )
            }
        )
        try apply(snapshot: convertedSnapshot)
    }

    private func activeTags(ids: [UUID]) throws -> [Tag] {
        try ids.map { id in
            guard let tag = storedTags.first(where: { $0.id == id && $0.deletedAt == nil }) else {
                throw ShoppingStoreError.tagNotFound(id)
            }
            return tag
        }
    }

    private func save() throws {
        do {
            try modelContext.save()
        } catch {
            throw ShoppingStoreError.saveFailed(error.localizedDescription)
        }
    }

    private func backfillLegacyVersions() throws {
        let currentVersion = Self.currentRecordSchemaVersion
        let legacyItems = storedItems.filter {
            $0.recordSchemaVersion < currentVersion
        }
        let legacyTags = storedTags.filter {
            $0.recordSchemaVersion < currentVersion
        }
        guard !legacyItems.isEmpty || !legacyTags.isEmpty else {
            return
        }

        for item in legacyItems {
            item.updatedAt = item.createdAt
            if item.lastEditorDeviceID.isEmpty {
                item.lastEditorDeviceID = deviceID
            }
            item.recordSchemaVersion = currentVersion
        }
        for tag in legacyTags {
            tag.updatedAt = tag.createdAt
            if tag.lastEditorDeviceID.isEmpty {
                tag.lastEditorDeviceID = deviceID
            }
            tag.recordSchemaVersion = currentVersion
        }

        do {
            try save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func advanceVersion(of item: ShoppingItem, now: Date) {
        item.updatedAt = max(now, item.updatedAt.addingTimeInterval(0.000_001))
        item.lastEditorDeviceID = deviceID
    }

    private func advanceVersion(of tag: Tag, now: Date) {
        tag.updatedAt = max(now, tag.updatedAt.addingTimeInterval(0.000_001))
        tag.lastEditorDeviceID = deviceID
    }

    private func sortedItems(_ items: [ShoppingItem]) -> [ShoppingItem] {
        items.sorted {
            if $0.sortOrder != $1.sortOrder {
                return $0.sortOrder < $1.sortOrder
            }
            return $0.createdAt > $1.createdAt
        }
    }
}
