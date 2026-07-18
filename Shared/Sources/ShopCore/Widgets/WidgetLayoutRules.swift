import Foundation

public enum WidgetLayoutFamily: Sendable {
    case small
    case medium
    case large
}

public enum WidgetLayoutRules {
    public static func activeColumns(
        for items: [WidgetSnapshotStore.Entry],
        family: WidgetLayoutFamily
    ) -> [[WidgetSnapshotStore.Entry]] {
        switch family {
        case .small:
            return [Array(items.prefix(3))]
        case .medium:
            // 2 columns × 2 rows; fill left column first when using two columns.
            let capped = Array(items.prefix(4))
            guard capped.count > 2 else { return [capped] }
            return split(capped, firstColumnCount: 2)
        case .large:
            // 2 columns × 6 rows; fill left column first.
            let capped = Array(items.prefix(12))
            guard capped.count > 6 else { return [capped] }
            return split(capped, firstColumnCount: 6)
        }
    }

    /// Reserved active rows so fewer items stay top-aligned without jumping.
    public static func activeReservedRows(family: WidgetLayoutFamily) -> Int {
        switch family {
        case .small: 3
        case .medium: 2
        case .large: 6
        }
    }

    /// Reserved row count for the pinned recently-completed band (keeps the divider fixed).
    public static func recentReservedRows(family: WidgetLayoutFamily) -> Int {
        switch family {
        case .small, .medium: 1
        case .large: 2
        }
    }

    /// Recently completed as columns (left-first).
    /// Small: 1 item. Medium: up to 3 columns × 1 row. Large: 1–2→1 col, 3–4→2 cols, 5–6→3 cols (2 rows max).
    public static func recentColumns(
        for items: [WidgetSnapshotStore.Entry],
        family: WidgetLayoutFamily
    ) -> [[WidgetSnapshotStore.Entry]] {
        switch family {
        case .small:
            return Array(items.prefix(1)).map { [$0] }
        case .medium:
            return Array(items.prefix(3)).map { [$0] }
        case .large:
            let capped = Array(items.prefix(6))
            guard !capped.isEmpty else { return [] }
            let columnCount: Int
            switch capped.count {
            case 1...2: columnCount = 1
            case 3...4: columnCount = 2
            default: columnCount = 3
            }
            return fillColumns(capped, columnCount: columnCount, maxRows: 2)
        }
    }

    public static func usesCompactTagDots(
        activeCount: Int,
        family: WidgetLayoutFamily
    ) -> Bool {
        switch family {
        case .small:
            return true
        case .medium:
            return activeCount > 2
        case .large:
            return activeCount > 6
        }
    }

    private static func split(
        _ items: [WidgetSnapshotStore.Entry],
        firstColumnCount: Int
    ) -> [[WidgetSnapshotStore.Entry]] {
        [
            Array(items.prefix(firstColumnCount)),
            Array(items.dropFirst(firstColumnCount))
        ].filter { !$0.isEmpty }
    }

    private static func fillColumns(
        _ items: [WidgetSnapshotStore.Entry],
        columnCount: Int,
        maxRows: Int
    ) -> [[WidgetSnapshotStore.Entry]] {
        var columns = Array(repeating: [WidgetSnapshotStore.Entry](), count: columnCount)
        for item in items {
            if let index = columns.firstIndex(where: { $0.count < maxRows }) {
                columns[index].append(item)
            }
        }
        return columns.filter { !$0.isEmpty }
    }
}
