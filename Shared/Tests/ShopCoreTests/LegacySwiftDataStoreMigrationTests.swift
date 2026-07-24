import XCTest
import SwiftData
@testable import ShopCore

final class LegacySwiftDataStoreMigrationTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("LegacySwiftDataStoreMigrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryRoot)
        temporaryRoot = nil
    }

    func testMigratesStoreAndSidecarsWhenDestinationMissing() throws {
        let sourceDir = temporaryRoot.appendingPathComponent("source", isDirectory: true)
        let destinationDir = temporaryRoot.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)

        let sourceStore = sourceDir.appendingPathComponent("default.store")
        try Data("store".utf8).write(to: sourceStore)
        try Data("shm".utf8).write(to: sourceDir.appendingPathComponent("default.store-shm"))
        try Data("wal".utf8).write(to: sourceDir.appendingPathComponent("default.store-wal"))

        let didMigrate = LegacySwiftDataStoreMigration.migrateIfNeeded(
            sourceStoreURLs: [sourceStore],
            destinationDirectory: destinationDir
        )

        XCTAssertTrue(didMigrate)
        XCTAssertEqual(
            try Data(contentsOf: destinationDir.appendingPathComponent("default.store")),
            Data("store".utf8)
        )
        XCTAssertEqual(
            try Data(contentsOf: destinationDir.appendingPathComponent("default.store-shm")),
            Data("shm".utf8)
        )
        XCTAssertEqual(
            try Data(contentsOf: destinationDir.appendingPathComponent("default.store-wal")),
            Data("wal".utf8)
        )
        // Source is left in place (copy, not move).
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceStore.path))
    }

    func testDoesNotOverwriteExistingDestinationStore() throws {
        let sourceDir = temporaryRoot.appendingPathComponent("source", isDirectory: true)
        let destinationDir = temporaryRoot.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)

        try Data("legacy".utf8).write(to: sourceDir.appendingPathComponent("default.store"))
        try Data("current".utf8).write(to: destinationDir.appendingPathComponent("default.store"))

        let didMigrate = LegacySwiftDataStoreMigration.migrateIfNeeded(
            sourceStoreURLs: [sourceDir.appendingPathComponent("default.store")],
            destinationDirectory: destinationDir
        )

        XCTAssertFalse(didMigrate)
        XCTAssertEqual(
            try Data(contentsOf: destinationDir.appendingPathComponent("default.store")),
            Data("current".utf8)
        )
    }

    func testSkipsEmptyDestinationPlaceholderAndEmptySource() throws {
        let sourceDir = temporaryRoot.appendingPathComponent("source", isDirectory: true)
        let destinationDir = temporaryRoot.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)

        try Data().write(to: destinationDir.appendingPathComponent("default.store"))
        try Data().write(to: sourceDir.appendingPathComponent("default.store"))

        let didMigrate = LegacySwiftDataStoreMigration.migrateIfNeeded(
            sourceStoreURLs: [sourceDir.appendingPathComponent("default.store")],
            destinationDirectory: destinationDir
        )

        XCTAssertFalse(didMigrate)
    }

    func testMigratePrivateStoreToAppGroupCopiesUsablePrivateData() throws {
        let privateDir = temporaryRoot.appendingPathComponent("private", isDirectory: true)
        let groupDir = temporaryRoot.appendingPathComponent("group", isDirectory: true)
        try FileManager.default.createDirectory(at: privateDir, withIntermediateDirectories: true)

        let privateStore = privateDir.appendingPathComponent("default.store")
        try Data("tagged-private".utf8).write(to: privateStore)

        let didMigrate = LegacySwiftDataStoreMigration.migrateIfNeeded(
            sourceStoreURLs: [privateStore],
            destinationDirectory: groupDir
        )

        XCTAssertTrue(didMigrate)
        XCTAssertEqual(
            try Data(contentsOf: groupDir.appendingPathComponent("default.store")),
            Data("tagged-private".utf8)
        )
    }

    func testMigratesOverBlankSwiftDataShellWithoutShoppingRows() throws {
        let sourceDir = temporaryRoot.appendingPathComponent("source", isDirectory: true)
        let destinationDir = temporaryRoot.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)

        let blankURL = destinationDir.appendingPathComponent("default.store")
        let schema = Schema([ShoppingItem.self, Tag.self])
        _ = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: blankURL)]
        )
        XCTAssertTrue(LegacySwiftDataStoreMigration.isUsableStore(at: blankURL))
        XCTAssertFalse(LegacySwiftDataStoreMigration.hasShoppingData(at: blankURL))

        let sourceStore = sourceDir.appendingPathComponent("default.store")
        try Data("private-with-tags".utf8).write(to: sourceStore)

        let didMigrate = LegacySwiftDataStoreMigration.migrateIfNeeded(
            sourceStoreURLs: [sourceStore],
            destinationDirectory: destinationDir
        )

        XCTAssertTrue(didMigrate)
        XCTAssertEqual(try Data(contentsOf: blankURL), Data("private-with-tags".utf8))
    }
}
