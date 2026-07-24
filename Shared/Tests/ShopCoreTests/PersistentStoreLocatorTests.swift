import XCTest
@testable import ShopCore

final class PersistentStoreLocatorTests: XCTestCase {
    func testFallbackStickyPrivateStaysPrivateWhenGroupIsEmpty() {
        let plan = PersistentStoreLocator.plan(
            groupAvailable: true,
            sticky: .applicationSupport,
            appGroupStoreUsable: false,
            privateStoreUsable: false
        )
        XCTAssertEqual(plan.location, .applicationSupport)
        XCTAssertFalse(plan.migratePrivateToAppGroup)
    }

    func testStickyPrivateHealsIntoEmptyAppGroupWhenPrivateHasData() {
        let plan = PersistentStoreLocator.plan(
            groupAvailable: true,
            sticky: .applicationSupport,
            appGroupStoreUsable: false,
            privateStoreUsable: true
        )
        XCTAssertEqual(plan.location, .appGroup)
        XCTAssertTrue(plan.migratePrivateToAppGroup)
    }

    func testFirstLaunchPrefersAppGroupWhenAvailable() {
        let plan = PersistentStoreLocator.plan(
            groupAvailable: true,
            sticky: nil,
            appGroupStoreUsable: false,
            privateStoreUsable: false
        )
        XCTAssertEqual(plan.location, .appGroup)
        XCTAssertFalse(plan.migratePrivateToAppGroup)
    }

    func testFirstLaunchMigratesOrphanPrivateDataIntoEmptyAppGroup() {
        // Quit/relaunch bug path: first session fell back to private and saved tags;
        // next session App Group opens empty unless we migrate first.
        let plan = PersistentStoreLocator.plan(
            groupAvailable: true,
            sticky: nil,
            appGroupStoreUsable: false,
            privateStoreUsable: true
        )
        XCTAssertEqual(plan.location, .appGroup)
        XCTAssertTrue(plan.migratePrivateToAppGroup)
    }

    func testBlankAppGroupShellDoesNotBlockPrivateHeal() {
        // `isUsableStore` is true for empty SwiftData schemas (~70KB), but
        // `hasShoppingData` is false — callers must pass that richer signal here.
        let plan = PersistentStoreLocator.plan(
            groupAvailable: true,
            sticky: .applicationSupport,
            appGroupStoreUsable: false,
            privateStoreUsable: true
        )
        XCTAssertEqual(plan.location, .appGroup)
        XCTAssertTrue(plan.migratePrivateToAppGroup)
    }

    func testUnavailableGroupUsesPrivateContainer() {
        let plan = PersistentStoreLocator.plan(
            groupAvailable: false,
            sticky: .appGroup,
            appGroupStoreUsable: false,
            privateStoreUsable: true
        )
        XCTAssertEqual(plan.location, .applicationSupport)
        XCTAssertFalse(plan.migratePrivateToAppGroup)
    }
}
