import Foundation

public struct ItemListSections: Equatable, Sendable {
    public let activeIDs: [UUID]
    public let archivedIDs: [UUID]
    public let activeGroups: [ItemListTagGroup]

    public var showsArchiveSection: Bool {
        !archivedIDs.isEmpty
    }

    public var isGrouped: Bool {
        !activeGroups.isEmpty
    }

    public enum DisplayRow: Equatable, Hashable, Sendable {
        case activeItem(UUID)
        case archiveHeader
        case archivedItem(UUID)
    }

    public var displayRows: [DisplayRow] {
        var rows: [DisplayRow] = []
        if isGrouped {
            for group in activeGroups {
                rows += group.itemIDs.map(DisplayRow.activeItem)
            }
        } else {
            rows += activeIDs.map(DisplayRow.activeItem)
        }
        if showsArchiveSection {
            rows.append(.archiveHeader)
            rows += archivedIDs.map(DisplayRow.archivedItem)
        }
        return rows
    }

    public static func derive(
        from filteredItems: [ShoppingItem],
        groupOption: DataStore.GroupOption = .none
    ) -> ItemListSections {
        let active = filteredItems.filter { !$0.isCompleted }
        let archived = filteredItems.filter(\.isCompleted)
        let groups: [ItemListTagGroup]
        switch groupOption {
        case .none:
            groups = []
        case .byTagSet, .byPrimaryTag, .byEachTag:
            groups = ItemListTagGroup.make(from: active, option: groupOption)
        }
        return ItemListSections(
            activeIDs: active.map(\.id),
            archivedIDs: archived.map(\.id),
            activeGroups: groups
        )
    }
}

public struct ItemListTagGroup: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let itemIDs: [UUID]

    public static func make(
        from activeItems: [ShoppingItem],
        option: DataStore.GroupOption
    ) -> [ItemListTagGroup] {
        switch option {
        case .none:
            return []
        case .byTagSet:
            return groupsByTagSet(activeItems)
        case .byPrimaryTag:
            return groupsByPrimaryTag(activeItems)
        case .byEachTag:
            return groupsByEachTag(activeItems)
        }
    }

    private static func groupsByTagSet(_ items: [ShoppingItem]) -> [ItemListTagGroup] {
        var buckets: [String: (title: String, ids: [UUID])] = [:]
        var order: [String] = []

        for item in items {
            let tags = item.tags.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            let key: String
            let title: String
            if tags.isEmpty {
                key = "__none__"
                title = ShopStrings.noTags
            } else {
                key = tags.map(\.id.uuidString).joined(separator: "|")
                title = tags.map(\.name).joined(separator: " · ")
            }
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = (title, [])
            }
            buckets[key]?.ids.append(item.id)
        }

        return orderedGroups(order: order, buckets: buckets)
    }

    private static func groupsByPrimaryTag(_ items: [ShoppingItem]) -> [ItemListTagGroup] {
        var buckets: [String: (title: String, ids: [UUID])] = [:]
        var order: [String] = []

        for item in items {
            let primary = item.tags
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                .first
            let key: String
            let title: String
            if let primary {
                key = primary.id.uuidString
                title = primary.name
            } else {
                key = "__none__"
                title = ShopStrings.noTags
            }
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = (title, [])
            }
            buckets[key]?.ids.append(item.id)
        }

        return orderedGroups(order: order, buckets: buckets)
    }

    private static func groupsByEachTag(_ items: [ShoppingItem]) -> [ItemListTagGroup] {
        var buckets: [String: (title: String, ids: [UUID])] = [:]
        var order: [String] = []

        for item in items {
            let tags = item.tags.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            if tags.isEmpty {
                let key = "__none__"
                if buckets[key] == nil {
                    order.append(key)
                    buckets[key] = (ShopStrings.noTags, [])
                }
                buckets[key]?.ids.append(item.id)
                continue
            }
            for tag in tags {
                let key = tag.id.uuidString
                if buckets[key] == nil {
                    order.append(key)
                    buckets[key] = (tag.name, [])
                }
                buckets[key]?.ids.append(item.id)
            }
        }

        return orderedGroups(order: order, buckets: buckets)
    }

    private static func orderedGroups(
        order: [String],
        buckets: [String: (title: String, ids: [UUID])]
    ) -> [ItemListTagGroup] {
        let sortedKeys = order.sorted { lhs, rhs in
            if lhs == "__none__" { return false }
            if rhs == "__none__" { return true }
            let left = buckets[lhs]?.title ?? lhs
            let right = buckets[rhs]?.title ?? rhs
            return left.localizedStandardCompare(right) == .orderedAscending
        }
        return sortedKeys.compactMap { key in
            guard let bucket = buckets[key] else { return nil }
            return ItemListTagGroup(id: key, title: bucket.title, itemIDs: bucket.ids)
        }
    }
}

public enum ItemListReorderPolicy {
    public static func canReorder(
        filter: DataStore.FilterOption,
        selectedTags: Set<UUID>,
        dateRange: ClosedRange<Date>?,
        searchIsActive: Bool = false,
        sortOption: DataStore.SortOption = .manual,
        groupOption: DataStore.GroupOption = .none
    ) -> Bool {
        guard sortOption == .manual,
              groupOption == .none,
              !searchIsActive,
              selectedTags.isEmpty,
              dateRange == nil else {
            return false
        }
        switch filter {
        case .all, .active:
            return true
        case .completed, .today, .week, .month:
            return false
        }
    }
}
