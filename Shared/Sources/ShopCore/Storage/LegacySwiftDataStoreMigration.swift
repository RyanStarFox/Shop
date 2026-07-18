import Foundation
#if os(macOS)
import Darwin
#endif

/// One-time copy of a pre-sandbox SwiftData store into the App Group container.
///
/// With an App Group entitlement, SwiftData's default `ModelConfiguration`
/// (`groupContainer: .automatic`) stores `default.store` under the group
/// Application Support directory. Older builds may still have left a store at
/// the unsandboxed `~/Library/Application Support/` location.
public enum LegacySwiftDataStoreMigration {
    public static let storeFileName = "default.store"
    public static let appGroupID = WidgetSnapshotStore.appGroupID

    private static let relatedSuffixes = ["", "-shm", "-wal"]

    /// Runs before `ModelContainer` creation. Safe to call repeatedly:
    /// copies only when the destination store is missing/empty and a source exists.
    @discardableResult
    public static func migrateIfNeeded(fileManager: FileManager = .default) -> Bool {
        #if os(macOS)
        guard let destinationDirectory = destinationApplicationSupportDirectory(fileManager: fileManager) else {
            return false
        }
        return migrateIfNeeded(
            sourceStoreURLs: legacySourceStoreURLs(fileManager: fileManager),
            destinationDirectory: destinationDirectory,
            fileManager: fileManager
        )
        #else
        return false
        #endif
    }

    /// Testable entry point: copy the first usable source store into `destinationDirectory`.
    @discardableResult
    public static func migrateIfNeeded(
        sourceStoreURLs: [URL],
        destinationDirectory: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        let destinationStore = destinationDirectory.appendingPathComponent(storeFileName)
        if isUsableStore(at: destinationStore, fileManager: fileManager) {
            return false
        }

        guard let sourceStore = sourceStoreURLs.first(where: {
            isUsableStore(at: $0, fileManager: fileManager)
        }) else {
            return false
        }

        // Never "migrate" a store onto itself.
        if sourceStore.standardizedFileURL == destinationStore.standardizedFileURL {
            return false
        }

        do {
            try fileManager.createDirectory(
                at: destinationDirectory,
                withIntermediateDirectories: true
            )
            for suffix in relatedSuffixes {
                let source = sourceStore.deletingLastPathComponent()
                    .appendingPathComponent(storeFileName + suffix)
                let destination = destinationDirectory
                    .appendingPathComponent(storeFileName + suffix)
                guard fileManager.fileExists(atPath: source.path) else { continue }
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.copyItem(at: source, to: destination)
            }
            return true
        } catch {
            return false
        }
    }

    public static func destinationApplicationSupportDirectory(
        fileManager: FileManager = .default
    ) -> URL? {
        fileManager
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("Library/Application Support", isDirectory: true)
    }

    public static func legacySourceStoreURLs(
        fileManager: FileManager = .default
    ) -> [URL] {
        #if os(macOS)
        guard let realHome = realUserHomeDirectory() else { return [] }
        let applicationSupport = realHome
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        let folderNames = ["", "Shop!", "Shop !", "ShopMac", "Shop"]
        return folderNames.map { name in
            if name.isEmpty {
                return applicationSupport.appendingPathComponent(storeFileName)
            }
            return applicationSupport
                .appendingPathComponent(name, isDirectory: true)
                .appendingPathComponent(storeFileName)
        }
        #else
        return []
        #endif
    }

    private static func isUsableStore(at url: URL, fileManager: FileManager) -> Bool {
        guard fileManager.fileExists(atPath: url.path) else { return false }
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize
        else {
            return false
        }
        return size > 0
    }

    #if os(macOS)
    private static func realUserHomeDirectory() -> URL? {
        guard let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir else {
            return nil
        }
        return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
    }
    #endif
}
