import Foundation

/// How long to keep completed archives and soft-deleted tombstones before cleanup.
public enum DataRetentionPolicy: String, CaseIterable, Sendable {
    case oneWeek
    case oneMonth
    case threeMonths
    case sixMonths
    case oneYear
    case forever

    public static let `default` = DataRetentionPolicy.oneYear

    /// Cutoff for pruning; `nil` means never prune.
    public func cutoff(relativeTo now: Date = Date(), calendar: Calendar = .current) -> Date? {
        switch self {
        case .forever:
            return nil
        case .oneWeek:
            return calendar.date(byAdding: .day, value: -7, to: now)
        case .oneMonth:
            return calendar.date(byAdding: .month, value: -1, to: now)
        case .threeMonths:
            return calendar.date(byAdding: .month, value: -3, to: now)
        case .sixMonths:
            return calendar.date(byAdding: .month, value: -6, to: now)
        case .oneYear:
            return calendar.date(byAdding: .year, value: -1, to: now)
        }
    }

    public var localizedTitle: String {
        switch self {
        case .oneWeek: ShopStrings.retentionOneWeek
        case .oneMonth: ShopStrings.retentionOneMonth
        case .threeMonths: ShopStrings.retentionThreeMonths
        case .sixMonths: ShopStrings.retentionSixMonths
        case .oneYear: ShopStrings.retentionOneYear
        case .forever: ShopStrings.retentionForever
        }
    }
}

public struct DataPruneResult: Equatable, Sendable {
    public var softDeletedItemCount: Int
    public var purgedItemCount: Int
    public var purgedTagCount: Int

    public init(
        softDeletedItemCount: Int = 0,
        purgedItemCount: Int = 0,
        purgedTagCount: Int = 0
    ) {
        self.softDeletedItemCount = softDeletedItemCount
        self.purgedItemCount = purgedItemCount
        self.purgedTagCount = purgedTagCount
    }

    public var didChange: Bool {
        softDeletedItemCount > 0 || purgedItemCount > 0 || purgedTagCount > 0
    }
}
