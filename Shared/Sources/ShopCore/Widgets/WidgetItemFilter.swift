import Foundation

public enum WidgetTagMatchMode: String, Codable, Sendable, CaseIterable {
    case any
    case all
}

public enum WidgetItemFilter {
    /// Sentinel for the “All Tags” configuration option.
    public static let allTagsSentinel = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    public static func filtered(
        items: [WidgetSnapshotStore.Entry],
        selectedTagIDs: Set<UUID>,
        matchMode: WidgetTagMatchMode
    ) -> [WidgetSnapshotStore.Entry] {
        if selectedTagIDs.isEmpty || selectedTagIDs.contains(allTagsSentinel) {
            return items
        }

        let effective = selectedTagIDs.subtracting([allTagsSentinel])
        guard !effective.isEmpty else { return items }

        let knownTagIDs = Set(items.flatMap { $0.tags.map(\.id) })
        let valid = effective.intersection(knownTagIDs)
        guard !valid.isEmpty else { return items }

        return items.filter { item in
            let ids = Set(item.tags.map(\.id))
            switch matchMode {
            case .any:
                return !ids.isDisjoint(with: valid)
            case .all:
                return valid.isSubset(of: ids)
            }
        }
    }
}
