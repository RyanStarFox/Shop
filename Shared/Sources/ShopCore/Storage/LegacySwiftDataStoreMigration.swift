import Foundation
#if os(macOS)
import Darwin
#endif

/// One-time copy of Mac shared data into the Team ID–prefixed App Group container.
///
/// macOS Sequoia treats unprefixed `group.*` containers as “other apps’ data” for
/// non–Mac App Store apps, prompting on every launch. Current stores live under
/// `H6AYG25QVN.group.com.ryanstarfox.shop`; older builds used `group.com.ryanstarfox.shop`.
public enum LegacySwiftDataStoreMigration {
    public static let storeFileName = "default.store"
    public static let appGroupID = WidgetSnapshotStore.appGroupID

    private static let relatedSuffixes = ["", "-shm", "-wal"]
    private static let widgetFileNames = [
        "widget_active_items.json",
        "widget_pending_completions.json",
        "widget_pending_restores.json",
        "widget_needs_sync.json",
    ]
    #if os(macOS)
    /// After one attempt to read the unprefixed legacy group, never call it again
    /// (Sequoia TCC for that container is process-lifetime only).
    private static let legacyGroupProbeDefaultsKey = "shop.mac.legacyUnprefixedGroupProbeCompleted"
    #endif

    /// Runs before `ModelContainer` creation. Safe to call repeatedly:
    /// copies only when the destination store is missing/empty and a source exists.
    @discardableResult
    public static func migrateIfNeeded(fileManager: FileManager = .default) -> Bool {
        #if os(macOS)
        guard let destinationRoot = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else {
            return false
        }
        let destinationDirectory = destinationRoot
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        let destinationStore = destinationDirectory.appendingPathComponent(storeFileName)

        if isUsableStore(at: destinationStore, fileManager: fileManager) {
            // New container already has data — never touch the legacy `group.*` ID again.
            return false
        }

        let defaults = UserDefaults.standard
        let shouldProbeLegacyGroup = !defaults.bool(forKey: legacyGroupProbeDefaultsKey)
        var sources: [URL] = []
        if shouldProbeLegacyGroup {
            if let legacyRoot = fileManager.containerURL(
                forSecurityApplicationGroupIdentifier: WidgetSnapshotStore.legacyAppGroupID
            ) {
                sources.append(
                    legacyRoot
                        .appendingPathComponent("Library/Application Support", isDirectory: true)
                        .appendingPathComponent(storeFileName)
                )
                copyMissingWidgetFiles(from: legacyRoot, into: destinationRoot, fileManager: fileManager)
            }
            defaults.set(true, forKey: legacyGroupProbeDefaultsKey)
        }
        sources.append(contentsOf: legacyApplicationSupportStoreURLs(fileManager: fileManager))

        return migrateIfNeeded(
            sourceStoreURLs: sources,
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

    /// Legacy store candidates for tests / direct callers.
    public static func legacySourceStoreURLs(
        fileManager: FileManager = .default
    ) -> [URL] {
        #if os(macOS)
        var urls: [URL] = []
        if let legacyRoot = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: WidgetSnapshotStore.legacyAppGroupID
        ) {
            urls.append(
                legacyRoot
                    .appendingPathComponent("Library/Application Support", isDirectory: true)
                    .appendingPathComponent(storeFileName)
            )
        }
        urls.append(contentsOf: legacyApplicationSupportStoreURLs(fileManager: fileManager))
        return urls
        #else
        return []
        #endif
    }

    #if os(macOS)
    public static func legacyApplicationSupportStoreURLs(
        fileManager: FileManager = .default
    ) -> [URL] {
        // No temporary sandbox exception: under App Sandbox these probes simply fail.
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
    }

    private static func copyMissingWidgetFiles(
        from legacyRoot: URL,
        into destinationRoot: URL,
        fileManager: FileManager
    ) {
        for name in widgetFileNames {
            let source = legacyRoot.appendingPathComponent(name)
            let destination = destinationRoot.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: source.path),
                  !fileManager.fileExists(atPath: destination.path)
            else { continue }
            try? fileManager.copyItem(at: source, to: destination)
        }
    }

    private static func realUserHomeDirectory() -> URL? {
        guard let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir else {
            return nil
        }
        return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
    }
    #endif

    private static func isUsableStore(at url: URL, fileManager: FileManager) -> Bool {
        guard fileManager.fileExists(atPath: url.path) else { return false }
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize
        else {
            return false
        }
        return size > 0
    }
}
