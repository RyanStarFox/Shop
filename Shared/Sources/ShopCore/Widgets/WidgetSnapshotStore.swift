import Foundation

/// Shared pending-item snapshot for Home Screen / Desktop widgets via App Group.
public enum WidgetSnapshotStore {
    public static let appGroupID = "group.com.ryanstarfox.shop"
    public static let recentlyCompletedLimit = 20

    private static let snapshotFileName = "widget_active_items.json"
    private static let pendingCompletionsFileName = "widget_pending_completions.json"
    private static let pendingRestoresFileName = "widget_pending_restores.json"
    private static let needsSyncFileName = "widget_needs_sync.json"

    private static let snapshotDefaultsKey = "widget_active_items"
    private static let pendingDefaultsKey = "widget_pending_completions"
    private static let pendingRestoresDefaultsKey = "widget_pending_restores"
    private static let needsSyncDefaultsKey = "widget_needs_sync"

    public struct TagInfo: Codable, Hashable, Sendable {
        public let id: UUID
        public let name: String
        public let colorHex: String

        public init(id: UUID, name: String, colorHex: String) {
            self.id = id
            self.name = name
            self.colorHex = colorHex
        }

        enum CodingKeys: String, CodingKey {
            case id, name, colorHex
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            name = try container.decode(String.self, forKey: .name)
            colorHex = try container.decode(String.self, forKey: .colorHex)
        }
    }

    public struct Entry: Codable, Identifiable, Hashable, Sendable {
        public let id: UUID
        public let name: String
        public let sortOrder: Int
        public let tags: [TagInfo]
        public let completedAt: Date?

        public init(
            id: UUID,
            name: String,
            sortOrder: Int,
            tags: [TagInfo] = [],
            completedAt: Date? = nil
        ) {
            self.id = id
            self.name = name
            self.sortOrder = sortOrder
            self.tags = tags
            self.completedAt = completedAt
        }

        enum CodingKeys: String, CodingKey {
            case id, name, sortOrder, tags, completedAt
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            name = try container.decode(String.self, forKey: .name)
            sortOrder = try container.decode(Int.self, forKey: .sortOrder)
            tags = try container.decodeIfPresent([TagInfo].self, forKey: .tags) ?? []
            completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        }
    }

    public struct Snapshot: Codable, Sendable {
        public var items: [Entry]
        public var recentlyCompleted: [Entry]
        public var availableTags: [TagInfo]
        public var updatedAt: Date

        public init(
            items: [Entry],
            recentlyCompleted: [Entry] = [],
            availableTags: [TagInfo] = [],
            updatedAt: Date = Date()
        ) {
            self.items = items
            self.recentlyCompleted = recentlyCompleted
            self.availableTags = availableTags
            self.updatedAt = updatedAt
        }

        enum CodingKeys: String, CodingKey {
            case items, recentlyCompleted, availableTags, updatedAt
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            items = try container.decodeIfPresent([Entry].self, forKey: .items) ?? []
            recentlyCompleted = try container.decodeIfPresent([Entry].self, forKey: .recentlyCompleted) ?? []
            availableTags = try container.decodeIfPresent([TagInfo].self, forKey: .availableTags) ?? []
            updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        }
    }

    private static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    /// App Group container is required for the widget and host app to share data.
    /// Sideloaded installs (e.g. AltStore resigning) often lose a working App Group.
    public static var isSharedContainerAvailable: Bool {
        containerURL != nil
    }

    private static var sharedDefaults: UserDefaults? {
        // Without a real App Group container, suiteName UserDefaults is not shared
        // across processes and silently causes empty widgets.
        guard isSharedContainerAvailable else { return nil }
        return UserDefaults(suiteName: appGroupID)
    }

    private static func fileURL(_ name: String) -> URL? {
        containerURL?.appendingPathComponent(name)
    }

    public static func publish(
        activeItems: [(id: UUID, name: String, sortOrder: Int, tags: [(id: UUID, name: String, colorHex: String)])],
        recentlyCompleted: [(id: UUID, name: String, sortOrder: Int, tags: [(id: UUID, name: String, colorHex: String)], completedAt: Date)],
        availableTags: [(id: UUID, name: String, colorHex: String)]
    ) {
        let entries = activeItems
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { item in
                Entry(
                    id: item.id,
                    name: item.name,
                    sortOrder: item.sortOrder,
                    tags: item.tags.map { TagInfo(id: $0.id, name: $0.name, colorHex: $0.colorHex) }
                )
            }

        let completedEntries = recentlyCompleted
            .sorted { $0.completedAt > $1.completedAt }
            .prefix(recentlyCompletedLimit)
            .map { item in
                Entry(
                    id: item.id,
                    name: item.name,
                    sortOrder: item.sortOrder,
                    tags: item.tags.map { TagInfo(id: $0.id, name: $0.name, colorHex: $0.colorHex) },
                    completedAt: item.completedAt
                )
            }

        let tags = availableTags.map { TagInfo(id: $0.id, name: $0.name, colorHex: $0.colorHex) }

        write(Snapshot(
            items: entries,
            recentlyCompleted: Array(completedEntries),
            availableTags: tags
        ))
    }

    public static func load() -> Snapshot {
        if let snapshot = loadSnapshotFromFile() {
            return snapshot
        }
        if let defaults = sharedDefaults,
           let data = defaults.data(forKey: snapshotDefaultsKey),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            return snapshot
        }
        return Snapshot(items: [])
    }

    public static func write(_ snapshot: Snapshot) {
        guard isSharedContainerAvailable else { return }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        if let url = fileURL(snapshotFileName) {
            try? data.write(to: url, options: .atomic)
        }
        sharedDefaults?.set(data, forKey: snapshotDefaultsKey)
    }

    /// Optimistically mark complete in the widget snapshot and queue for the main app.
    @discardableResult
    public static func markCompleteInSnapshot(itemID: UUID) -> Bool {
        var snapshot = load()
        guard let index = snapshot.items.firstIndex(where: { $0.id == itemID }) else {
            return false
        }
        let item = snapshot.items.remove(at: index)
        let completed = Entry(
            id: item.id,
            name: item.name,
            sortOrder: item.sortOrder,
            tags: item.tags,
            completedAt: Date()
        )
        snapshot.recentlyCompleted.insert(completed, at: 0)
        if snapshot.recentlyCompleted.count > recentlyCompletedLimit {
            snapshot.recentlyCompleted = Array(snapshot.recentlyCompleted.prefix(recentlyCompletedLimit))
        }
        snapshot.updatedAt = Date()
        write(snapshot)
        enqueuePendingCompletion(itemID)
        markNeedsSync()
        return true
    }

    /// Optimistically restore a completed item in the widget snapshot and queue for the main app.
    @discardableResult
    public static func restoreInSnapshot(itemID: UUID) -> Bool {
        var snapshot = load()
        guard let index = snapshot.recentlyCompleted.firstIndex(where: { $0.id == itemID }) else {
            return false
        }
        let item = snapshot.recentlyCompleted.remove(at: index)
        let restored = Entry(
            id: item.id,
            name: item.name,
            sortOrder: item.sortOrder,
            tags: item.tags,
            completedAt: nil
        )
        let insertIndex = snapshot.items.firstIndex { $0.sortOrder > restored.sortOrder } ?? snapshot.items.endIndex
        snapshot.items.insert(restored, at: insertIndex)
        snapshot.updatedAt = Date()
        write(snapshot)
        enqueuePendingRestore(itemID)
        markNeedsSync()
        return true
    }

    public static func enqueuePendingCompletion(_ itemID: UUID) {
        var pending = loadPendingCompletions()
        if !pending.contains(itemID) {
            pending.append(itemID)
            savePendingCompletions(pending)
        }
    }

    public static func loadPendingCompletions() -> [UUID] {
        loadUUIDList(fileName: pendingCompletionsFileName, defaultsKey: pendingDefaultsKey)
    }

    public static func clearPendingCompletions() {
        savePendingCompletions([])
    }

    public static func enqueuePendingRestore(_ itemID: UUID) {
        var pending = loadPendingRestores()
        if !pending.contains(itemID) {
            pending.append(itemID)
            savePendingRestores(pending)
        }
    }

    public static func loadPendingRestores() -> [UUID] {
        loadUUIDList(fileName: pendingRestoresFileName, defaultsKey: pendingRestoresDefaultsKey)
    }

    public static func clearPendingRestores() {
        savePendingRestores([])
    }

    public static var needsSync: Bool {
        loadNeedsSync()
    }

    public static func markNeedsSync() {
        saveNeedsSync(true)
    }

    public static func clearNeedsSync() {
        saveNeedsSync(false)
    }

    public static func loadNeedsSync() -> Bool {
        if let url = fileURL(needsSyncFileName),
           let data = try? Data(contentsOf: url),
           let flag = try? JSONDecoder().decode(Bool.self, from: data) {
            return flag
        }
        return sharedDefaults?.bool(forKey: needsSyncDefaultsKey) ?? false
    }

    private static func loadSnapshotFromFile() -> Snapshot? {
        guard let url = fileURL(snapshotFileName),
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        else {
            return nil
        }
        return snapshot
    }

    private static func savePendingCompletions(_ ids: [UUID]) {
        saveUUIDList(ids, fileName: pendingCompletionsFileName, defaultsKey: pendingDefaultsKey)
    }

    private static func savePendingRestores(_ ids: [UUID]) {
        saveUUIDList(ids, fileName: pendingRestoresFileName, defaultsKey: pendingRestoresDefaultsKey)
    }

    private static func loadUUIDList(fileName: String, defaultsKey: String) -> [UUID] {
        if let url = fileURL(fileName),
           let data = try? Data(contentsOf: url),
           let ids = try? JSONDecoder().decode([UUID].self, from: data) {
            return ids
        }
        if let defaults = sharedDefaults,
           let data = defaults.data(forKey: defaultsKey),
           let ids = try? JSONDecoder().decode([UUID].self, from: data) {
            return ids
        }
        return []
    }

    private static func saveUUIDList(_ ids: [UUID], fileName: String, defaultsKey: String) {
        guard let data = try? JSONEncoder().encode(ids) else { return }
        if let url = fileURL(fileName) {
            try? data.write(to: url, options: .atomic)
        }
        sharedDefaults?.set(data, forKey: defaultsKey)
    }

    private static func saveNeedsSync(_ value: Bool) {
        if let data = try? JSONEncoder().encode(value),
           let url = fileURL(needsSyncFileName) {
            try? data.write(to: url, options: .atomic)
        }
        sharedDefaults?.set(value, forKey: needsSyncDefaultsKey)
    }
}
