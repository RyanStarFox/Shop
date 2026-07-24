import Foundation

/// Chooses between the App Group SwiftData store and the private app container.
///
/// Sideloaded installs often fail App Group on first launch and fall back to the
/// private container. If a later launch opens an empty App Group store instead,
/// tagged items (and all local edits) appear to vanish after quit/relaunch.
public enum PersistentStoreLocation: String, Sendable {
    case appGroup
    case applicationSupport
}

public struct PersistentStorePlan: Equatable, Sendable {
    public let location: PersistentStoreLocation
    /// Copy private `default.store` (+ sidecars) into the App Group when healing.
    public let migratePrivateToAppGroup: Bool

    public init(location: PersistentStoreLocation, migratePrivateToAppGroup: Bool) {
        self.location = location
        self.migratePrivateToAppGroup = migratePrivateToAppGroup
    }
}

public enum PersistentStoreLocator: Sendable {
    public static let preferenceKey = "shop.swiftData.storeLocation"

    /// Pure decision used by `ShoppingStore` and unit tests.
    public static func plan(
        groupAvailable: Bool,
        sticky: PersistentStoreLocation?,
        appGroupStoreUsable: Bool,
        privateStoreUsable: Bool
    ) -> PersistentStorePlan {
        if let sticky {
            switch sticky {
            case .applicationSupport:
                // Heal: private has data, App Group is empty/missing → move into group.
                if groupAvailable, privateStoreUsable, !appGroupStoreUsable {
                    return PersistentStorePlan(
                        location: .appGroup,
                        migratePrivateToAppGroup: true
                    )
                }
                return PersistentStorePlan(
                    location: .applicationSupport,
                    migratePrivateToAppGroup: false
                )
            case .appGroup:
                if groupAvailable {
                    if !appGroupStoreUsable, privateStoreUsable {
                        return PersistentStorePlan(
                            location: .appGroup,
                            migratePrivateToAppGroup: true
                        )
                    }
                    return PersistentStorePlan(
                        location: .appGroup,
                        migratePrivateToAppGroup: false
                    )
                }
                return PersistentStorePlan(
                    location: .applicationSupport,
                    migratePrivateToAppGroup: false
                )
            }
        }

        guard groupAvailable else {
            return PersistentStorePlan(
                location: .applicationSupport,
                migratePrivateToAppGroup: false
            )
        }

        if !appGroupStoreUsable, privateStoreUsable {
            return PersistentStorePlan(
                location: .appGroup,
                migratePrivateToAppGroup: true
            )
        }

        return PersistentStorePlan(
            location: .appGroup,
            migratePrivateToAppGroup: false
        )
    }

    public static func loadSticky(
        defaults: UserDefaults = .standard
    ) -> PersistentStoreLocation? {
        guard let raw = defaults.string(forKey: preferenceKey) else { return nil }
        return PersistentStoreLocation(rawValue: raw)
    }

    public static func saveSticky(
        _ location: PersistentStoreLocation,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(location.rawValue, forKey: preferenceKey)
    }
}
