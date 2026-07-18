import XCTest
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
}
