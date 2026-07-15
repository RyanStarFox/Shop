import Foundation

public struct ItemListSections: Equatable, Sendable {
    public let activeIDs: [UUID]
    public let archivedIDs: [UUID]

    public var showsArchiveSection: Bool {
        !archivedIDs.isEmpty
    }

    public enum DisplayRow: Equatable, Sendable {
        case activeItem(UUID)
        case archiveHeader
        case archivedItem(UUID)
    }

    public var displayRows: [DisplayRow] {
        var rows = activeIDs.map(DisplayRow.activeItem)
        if showsArchiveSection {
            rows.append(.archiveHeader)
            rows += archivedIDs.map(DisplayRow.archivedItem)
        }
        return rows
    }

    public static func derive(from filteredItems: [ShoppingItem]) -> ItemListSections {
        ItemListSections(
            activeIDs: filteredItems.filter { !$0.isCompleted }.map(\.id),
            archivedIDs: filteredItems.filter(\.isCompleted).map(\.id)
        )
    }
}

public enum ItemListReorderPolicy {
    public static func canReorder(
        filter: DataStore.FilterOption,
        selectedTags: Set<UUID>,
        dateRange: ClosedRange<Date>?,
        searchIsActive: Bool = false,
        sortOption: DataStore.SortOption = .manual
    ) -> Bool {
        guard sortOption == .manual,
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
