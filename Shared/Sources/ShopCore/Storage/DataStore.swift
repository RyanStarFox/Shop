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
    @Published public var selectedFilter: FilterOption = .all {
        didSet { persistListPreferences() }
    }
    @Published public var selectedTags: Set<UUID> = [] {
        didSet { persistListPreferences() }
    }
    @Published public var tagMatchMode: WidgetTagMatchMode = .any {
        didSet { persistListPreferences() }
    }
    @Published public var dateRange: ClosedRange<Date>? {
        didSet { persistListPreferences() }
    }
    @Published public var sortOption: SortOption = .manual {
        didSet { persistListPreferences() }
    }
    @Published public var groupOption: GroupOption = .none {
        didSet { persistListPreferences() }
    }
    @Published public var dataRetention: DataRetentionPolicy = .default {
        didSet {
            persistListPreferences()
            if !isRestoringPreferences {
                pruneExpiredData()
            }
        }
    }
    private var localMutationObservers: [UUID: () -> Void] = [:]
    private let persistsPreferences: Bool
    private var isRestoringPreferences = false

    public enum FilterOption: String, CaseIterable {
        case all
        case active
        case completed
        case today
        case week
        case month
    }

    public enum SortOption: String, CaseIterable, Sendable {
        case manual
        case createdNewest
        case createdOldest
        case nameAscending
        case nameDescending
    }

    public enum GroupOption: String, CaseIterable, Sendable {
        /// Flat list (existing behavior).
        case none
        /// Items with the exact same tag set share a section.
        case byTagSet
        /// Group by the item's first tag; untitled items share one section.
        case byPrimaryTag
        /// One section per tag; multi-tag items appear in each matching section.
        case byEachTag
    }

    public init(inMemory: Bool = false, deviceID: String? = nil) {
        persistsPreferences = !inMemory
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
        restoreListPreferences()
        // Do not prune on launch — soft-deletes can race ahead of WebDAV pull.
        // App lifecycle and SyncCoordinator prune after a successful sync instead.
    }

    public func fetchData() {
        activeItems = shoppingStore.activeItems
        archivedItems = shoppingStore.archivedItems
        items = activeItems + archivedItems
        tags = shoppingStore.tags
    }

    /// Soft-deletes expired completed items and physically purges aged tombstones.
    @discardableResult
    public func pruneExpiredData(
        now: Date = Date(),
        notifyObservers: Bool = true
    ) -> DataPruneResult {
        do {
            let result = try shoppingStore.pruneExpiredData(
                retention: dataRetention,
                now: now
            )
            if result.didChange {
                lastError = nil
                if notifyObservers, result.softDeletedItemCount > 0 {
                    localMutationObservers.values.forEach { $0() }
                }
                fetchData()
            }
            return result
        } catch let error as ShoppingStoreError {
            lastError = error
        } catch {
            lastError = .saveFailed(error.localizedDescription)
        }
        fetchData()
        return DataPruneResult()
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
                let ids = Set(item.tags.map(\.id))
                switch tagMatchMode {
                case .any:
                    return !selectedTags.isDisjoint(with: ids)
                case .all:
                    return selectedTags.isSubset(of: ids)
                }
            }
        }

        if let range = dateRange {
            result = result.filter { range.contains($0.createdAt) }
        }

        return sorted(result)
    }

    private func sorted(_ items: [ShoppingItem]) -> [ShoppingItem] {
        switch sortOption {
        case .manual:
            return items
        case .createdNewest:
            return items.sorted { $0.createdAt > $1.createdAt }
        case .createdOldest:
            return items.sorted { $0.createdAt < $1.createdAt }
        case .nameAscending:
            return items.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        case .nameDescending:
            return items.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedDescending
            }
        }
    }

    // MARK: - Item operations

    public func addItem(name: String, tags: [Tag] = [], createdAt: Date? = nil) {
        performMutation {
            _ = try shoppingStore.addItem(
                name: name,
                tagIDs: tags.map(\.id),
                createdAt: createdAt
            )
        }
    }

    public func toggleItem(_ item: ShoppingItem) {
        setCompleted(item, completed: !item.isCompleted, presentUndo: { _ in })
    }

    public func setCompleted(
        _ item: ShoppingItem,
        completed: Bool,
        presentUndo: (UndoAction) -> Void
    ) {
        let previousIsCompleted = item.isCompleted
        let previousCompletedAt = item.completedAt
        let succeeded = performMutation {
            try shoppingStore.setCompleted(
                itemID: item.id,
                completed: completed
            )
        }
        guard succeeded else { return }
        presentUndo(
            ShoppingUndo.undoCompletion(
                itemID: item.id,
                previousIsCompleted: previousIsCompleted,
                previousCompletedAt: previousCompletedAt,
                store: shoppingStore
            )
        )
    }

    public func setCompleted(
        _ itemIDs: [UUID],
        completed: Bool,
        presentUndo: (UndoAction) -> Void
    ) {
        let previous: [(UUID, Bool, Date?)] = itemIDs.compactMap { id in
            guard let item = items.first(where: { $0.id == id }) else { return nil }
            guard item.isCompleted != completed else { return nil }
            return (id, item.isCompleted, item.completedAt)
        }
        guard !previous.isEmpty else { return }
        let succeeded = performMutation {
            _ = try shoppingStore.setCompleted(itemIDs: itemIDs, completed: completed)
        }
        guard succeeded else { return }
        presentUndo(
            ShoppingUndo.undoBatchCompletion(
                previousStates: previous.map { ($0.0, $0.1, $0.2) },
                store: shoppingStore
            )
        )
    }

    public func deleteItem(
        _ item: ShoppingItem,
        presentUndo: (UndoAction) -> Void = { _ in }
    ) {
        let itemID = item.id
        let succeeded = performMutation {
            try shoppingStore.softDeleteItem(itemID: itemID)
        }
        guard succeeded else { return }
        presentUndo(
            ShoppingUndo.undoItemDelete(
                itemID: itemID,
                store: shoppingStore
            )
        )
    }

    public func deleteItems(
        _ itemIDs: [UUID],
        presentUndo: (UndoAction) -> Void = { _ in }
    ) {
        let existing = itemIDs.filter { id in items.contains(where: { $0.id == id }) }
        guard !existing.isEmpty else { return }
        let succeeded = performMutation {
            _ = try shoppingStore.softDeleteItems(itemIDs: existing)
        }
        guard succeeded else { return }
        presentUndo(
            ShoppingUndo.undoBatchItemDelete(
                itemIDs: existing,
                store: shoppingStore
            )
        )
    }

    public func addTag(_ tag: Tag, toItemIDs itemIDs: [UUID], presentUndo: (UndoAction) -> Void) {
        let previous: [(UUID, [UUID])] = itemIDs.compactMap { id in
            guard let item = items.first(where: { $0.id == id }) else { return nil }
            guard !item.tags.contains(where: { $0.id == tag.id }) else { return nil }
            return (id, item.tags.map(\.id))
        }
        guard !previous.isEmpty else { return }
        let succeeded = performMutation {
            _ = try shoppingStore.addTag(tagID: tag.id, toItemIDs: itemIDs)
        }
        guard succeeded else { return }
        presentUndo(
            ShoppingUndo.undoBatchTagMembership(
                previousMemberships: previous.map { ($0.0, $0.1) },
                store: shoppingStore
            )
        )
    }

    public func removeTag(_ tag: Tag, fromItemIDs itemIDs: [UUID], presentUndo: (UndoAction) -> Void) {
        let previous: [(UUID, [UUID])] = itemIDs.compactMap { id in
            guard let item = items.first(where: { $0.id == id }) else { return nil }
            guard item.tags.contains(where: { $0.id == tag.id }) else { return nil }
            return (id, item.tags.map(\.id))
        }
        guard !previous.isEmpty else { return }
        let succeeded = performMutation {
            _ = try shoppingStore.removeTag(tagID: tag.id, fromItemIDs: itemIDs)
        }
        guard succeeded else { return }
        presentUndo(
            ShoppingUndo.undoBatchTagMembership(
                previousMemberships: previous.map { ($0.0, $0.1) },
                store: shoppingStore
            )
        )
    }

    public func updateItem(
        _ item: ShoppingItem,
        name: String? = nil,
        tags: [Tag]? = nil,
        createdAt: Date? = nil,
        completedAt: Date? = nil,
        updateCompletedAt: Bool = false,
        presentUndo: ((UndoAction) -> Void)? = nil
    ) {
        let previousName = item.name
        let previousTagIDs = item.tags.map(\.id)
        let previousCreatedAt = item.createdAt
        let previousIsCompleted = item.isCompleted
        let previousCompletedAt = item.completedAt

        let succeeded = performMutation {
            try shoppingStore.updateItem(
                itemID: item.id,
                name: name,
                tagIDs: tags?.map(\.id),
                createdAt: createdAt,
                completedAt: completedAt,
                updateCompletedAt: updateCompletedAt
            )
        }
        guard succeeded, let presentUndo else { return }
        presentUndo(
            ShoppingUndo.undoItemEdit(
                itemID: item.id,
                previousName: previousName,
                previousTagIDs: previousTagIDs,
                previousCreatedAt: previousCreatedAt,
                previousIsCompleted: previousIsCompleted,
                previousCompletedAt: previousCompletedAt,
                store: shoppingStore
            )
        )
    }

    public func moveItems(from source: IndexSet, to destination: Int) {
        guard ItemListReorderPolicy.canReorder(
            filter: selectedFilter,
            selectedTags: selectedTags,
            dateRange: dateRange,
            sortOption: sortOption,
            groupOption: groupOption
        ) else {
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

    public func deleteTag(
        _ tag: Tag,
        presentUndo: (UndoAction) -> Void = { _ in }
    ) {
        let linkedItemIDs = items
            .filter { item in
                item.tags.contains { $0.id == tag.id }
            }
            .map(\.id)
        let tagID = tag.id
        let succeeded = performMutation {
            try shoppingStore.deleteTag(id: tagID)
        }
        guard succeeded else { return }
        presentUndo(
            ShoppingUndo.undoTagDelete(
                tagID: tagID,
                linkedItemIDs: linkedItemIDs,
                store: shoppingStore
            )
        )
    }

    public func performUndoMutation(_ mutation: () throws -> Void) throws {
        do {
            try mutation()
            lastError = nil
            localMutationObservers.values.forEach { $0() }
        } catch let error as ShoppingStoreError {
            lastError = error
            throw error
        } catch {
            lastError = .saveFailed(error.localizedDescription)
            throw error
        }
        fetchData()
        publishWidgetSnapshot()
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
            applyRemoteSnapshot(snapshot)
        } catch {
            lastError = .fetchFailed(error.localizedDescription)
        }
    }

    @discardableResult
    public func addLocalMutationObserver(
        _ observer: @escaping () -> Void
    ) -> UUID {
        let id = UUID()
        localMutationObservers[id] = observer
        return id
    }

    public func removeLocalMutationObserver(_ id: UUID) {
        localMutationObservers.removeValue(forKey: id)
    }

    public func applyRemoteSnapshot(_ snapshot: SyncSnapshot) {
        let before = try? shoppingStore.makeSnapshot()
        do {
            try shoppingStore.apply(snapshot: snapshot)
            lastError = nil
        } catch let error as ShoppingStoreError {
            lastError = error
        } catch {
            lastError = .saveFailed(error.localizedDescription)
        }
        fetchData()
        publishWidgetSnapshot()
        let after = try? shoppingStore.makeSnapshot()
        // Ignore generatedAt — makeSnapshot always stamps "now".
        if before?.items != after?.items || before?.tags != after?.tags {
            // Watch / import changes should schedule WebDAV upload like local edits.
            localMutationObservers.values.forEach { $0() }
        }
    }

    @discardableResult
    private func performMutation(_ mutation: () throws -> Void) -> Bool {
        do {
            try mutation()
            lastError = nil
            localMutationObservers.values.forEach { $0() }
            fetchData()
            publishWidgetSnapshot()
            return true
        } catch let error as ShoppingStoreError {
            lastError = error
        } catch {
            lastError = .saveFailed(error.localizedDescription)
        }
        fetchData()
        publishWidgetSnapshot()
        return false
    }

    /// Writes active items, recently completed, and tags for Home Screen / Desktop widgets.
    public func publishWidgetSnapshot() {
        let mappedTags: ([Tag]) -> [(id: UUID, name: String, colorHex: String)] = { tags in
            tags
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                .map { (id: $0.id, name: $0.name, colorHex: $0.colorHex) }
        }

        let completed = archivedItems
            .compactMap { item -> (id: UUID, name: String, sortOrder: Int, tags: [(id: UUID, name: String, colorHex: String)], completedAt: Date)? in
                guard let completedAt = item.completedAt else { return nil }
                return (
                    id: item.id,
                    name: item.name,
                    sortOrder: item.sortOrder,
                    tags: mappedTags(item.tags),
                    completedAt: completedAt
                )
            }
            .sorted { $0.completedAt > $1.completedAt }

        WidgetSnapshotStore.publish(
            activeItems: activeItems.map { item in
                (
                    id: item.id,
                    name: item.name,
                    sortOrder: item.sortOrder,
                    tags: mappedTags(item.tags)
                )
            },
            recentlyCompleted: completed,
            availableTags: tags.map { (id: $0.id, name: $0.name, colorHex: $0.colorHex) }
        )
    }

    /// Applies completions queued by the widget extension, then refreshes the snapshot.
    public func applyPendingWidgetCompletions() {
        applyPendingWidgetMutations()
    }

    /// Applies widget completion and restore queues, then republishes the authoritative snapshot.
    public func applyPendingWidgetMutations() {
        let completions = WidgetSnapshotStore.loadPendingCompletions()
        let restores = WidgetSnapshotStore.loadPendingRestores()
        guard !completions.isEmpty || !restores.isEmpty else {
            publishWidgetSnapshot()
            return
        }

        for id in completions {
            do {
                try shoppingStore.setCompleted(itemID: id, completed: true)
            } catch {
                // Item may already be completed or deleted; ignore.
            }
        }
        WidgetSnapshotStore.clearPendingCompletions()

        for id in restores {
            do {
                try shoppingStore.setCompleted(itemID: id, completed: false)
            } catch {
                // Item may already be pending or deleted; ignore.
            }
        }
        WidgetSnapshotStore.clearPendingRestores()

        lastError = nil
        localMutationObservers.values.forEach { $0() }
        fetchData()
        publishWidgetSnapshot()
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

    // MARK: - List preferences

    private enum PreferenceKey {
        static let filter = "shop.list.filter"
        static let sort = "shop.list.sort"
        static let group = "shop.list.group"
        static let selectedTags = "shop.list.selectedTags"
        static let tagMatchMode = "shop.list.tagMatchMode"
        static let dateRangeStart = "shop.list.dateRange.start"
        static let dateRangeEnd = "shop.list.dateRange.end"
        static let dataRetention = "shop.data.retention"
    }

    private func restoreListPreferences() {
        guard persistsPreferences else { return }
        isRestoringPreferences = true
        defer { isRestoringPreferences = false }

        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: PreferenceKey.filter),
           let value = FilterOption(rawValue: raw) {
            selectedFilter = value
        }
        if let raw = defaults.string(forKey: PreferenceKey.sort),
           let value = SortOption(rawValue: raw) {
            sortOption = value
        }
        if let raw = defaults.string(forKey: PreferenceKey.group),
           let value = GroupOption(rawValue: raw) {
            groupOption = value
        }
        if let raw = defaults.string(forKey: PreferenceKey.dataRetention),
           let value = DataRetentionPolicy(rawValue: raw) {
            dataRetention = value
        }
        if let raw = defaults.array(forKey: PreferenceKey.selectedTags) as? [String] {
            selectedTags = Self.validSelectedTagIDs(
                Set(raw.compactMap(UUID.init(uuidString:))),
                availableTags: tags
            )
            defaults.set(
                selectedTags.map(\.uuidString).sorted(),
                forKey: PreferenceKey.selectedTags
            )
        }
        if let raw = defaults.string(forKey: PreferenceKey.tagMatchMode),
           let value = WidgetTagMatchMode(rawValue: raw) {
            tagMatchMode = value
        }
        if let start = defaults.object(forKey: PreferenceKey.dateRangeStart) as? Date,
           let end = defaults.object(forKey: PreferenceKey.dateRangeEnd) as? Date,
           start <= end {
            dateRange = start...end
        }
    }

    static func validSelectedTagIDs(
        _ selectedIDs: Set<UUID>,
        availableTags: [Tag]
    ) -> Set<UUID> {
        selectedIDs.intersection(availableTags.map(\.id))
    }

    private func persistListPreferences() {
        guard persistsPreferences, !isRestoringPreferences else { return }
        let defaults = UserDefaults.standard
        defaults.set(selectedFilter.rawValue, forKey: PreferenceKey.filter)
        defaults.set(sortOption.rawValue, forKey: PreferenceKey.sort)
        defaults.set(groupOption.rawValue, forKey: PreferenceKey.group)
        defaults.set(dataRetention.rawValue, forKey: PreferenceKey.dataRetention)
        defaults.set(
            selectedTags.map(\.uuidString).sorted(),
            forKey: PreferenceKey.selectedTags
        )
        defaults.set(tagMatchMode.rawValue, forKey: PreferenceKey.tagMatchMode)
        if let dateRange {
            defaults.set(dateRange.lowerBound, forKey: PreferenceKey.dateRangeStart)
            defaults.set(dateRange.upperBound, forKey: PreferenceKey.dateRangeEnd)
        } else {
            defaults.removeObject(forKey: PreferenceKey.dateRangeStart)
            defaults.removeObject(forKey: PreferenceKey.dateRangeEnd)
        }
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
