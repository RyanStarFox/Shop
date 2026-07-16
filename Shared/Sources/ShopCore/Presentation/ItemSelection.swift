import Foundation

public enum TagMembership: Equatable, Sendable {
    case all
    case some
    case none
}

public enum ItemSelection {
    public static func visualOrderedIDs(from sections: ItemListSections) -> [UUID] {
        var ids: [UUID] = []
        if sections.isGrouped {
            for group in sections.activeGroups {
                ids.append(contentsOf: group.itemIDs)
            }
        } else {
            ids.append(contentsOf: sections.activeIDs)
        }
        ids.append(contentsOf: sections.archivedIDs)
        return ids
    }

    public static func range(from start: UUID, to end: UUID, in order: [UUID]) -> [UUID] {
        guard let i = order.firstIndex(of: start), let j = order.firstIndex(of: end) else {
            return []
        }
        let lower = min(i, j)
        let upper = max(i, j)
        return Array(order[lower...upper])
    }

    public static func membership(
        of tagID: UUID,
        in items: [(id: UUID, tagIDs: Set<UUID>)]
    ) -> TagMembership {
        guard !items.isEmpty else { return .none }
        let hits = items.filter { $0.tagIDs.contains(tagID) }.count
        if hits == 0 { return .none }
        if hits == items.count { return .all }
        return .some
    }

    public static func prunedSelection(_ selection: Set<UUID>, visibleIDs: Set<UUID>) -> Set<UUID> {
        selection.intersection(visibleIDs)
    }
}
