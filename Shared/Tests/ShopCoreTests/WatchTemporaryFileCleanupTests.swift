import Foundation
import XCTest
@testable import ShopCore

final class WatchTemporaryFileCleanupTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 200_000)
    private let staleAge: TimeInterval = 24 * 60 * 60
    private let directory = URL(fileURLWithPath: "/tmp/shop-watch-sync", isDirectory: true)
    private let prefix = "shop-watch-snapshot-"

    func testOldOutstandingFileIsNotSelected() {
        let file = record(name: "\(prefix)queued.json", age: staleAge + 1)
        let alternatePath = directory
            .appendingPathComponent("subdirectory")
            .appendingPathComponent("..")
            .appendingPathComponent(file.url.lastPathComponent)

        let candidates = WatchTemporaryFileCleanup.candidates(
            from: [file],
            outstandingURLs: [alternatePath],
            serviceDirectory: directory,
            filePrefix: prefix,
            olderThan: staleAge,
            now: now
        )

        XCTAssertTrue(candidates.isEmpty)
    }

    func testOldNonOutstandingFileIsSelected() {
        let file = record(name: "\(prefix)orphan.json", age: staleAge + 1)

        let candidates = WatchTemporaryFileCleanup.candidates(
            from: [file],
            outstandingURLs: [],
            serviceDirectory: directory,
            filePrefix: prefix,
            olderThan: staleAge,
            now: now
        )

        XCTAssertEqual(candidates, [file.url])
    }

    func testNewFileIsNotSelected() {
        let file = record(name: "\(prefix)new.json", age: staleAge - 1)

        let candidates = WatchTemporaryFileCleanup.candidates(
            from: [file],
            outstandingURLs: [],
            serviceDirectory: directory,
            filePrefix: prefix,
            olderThan: staleAge,
            now: now
        )

        XCTAssertTrue(candidates.isEmpty)
    }

    func testOtherPrefixIsNotSelected() {
        let file = record(name: "other-service.json", age: staleAge + 1)

        let candidates = WatchTemporaryFileCleanup.candidates(
            from: [file],
            outstandingURLs: [],
            serviceDirectory: directory,
            filePrefix: prefix,
            olderThan: staleAge,
            now: now
        )

        XCTAssertTrue(candidates.isEmpty)
    }

    private func record(name: String, age: TimeInterval) -> WatchTemporaryFileRecord {
        WatchTemporaryFileRecord(
            url: directory.appendingPathComponent(name),
            modifiedAt: now.addingTimeInterval(-age)
        )
    }
}
