import Foundation

public struct WatchTemporaryFileRecord: Equatable, Sendable {
    public let url: URL
    public let modifiedAt: Date

    public init(url: URL, modifiedAt: Date) {
        self.url = url
        self.modifiedAt = modifiedAt
    }
}

public enum WatchTemporaryFileCleanup {
    public static func candidates(
        from files: [WatchTemporaryFileRecord],
        outstandingURLs: [URL],
        serviceDirectory: URL,
        filePrefix: String,
        olderThan staleAge: TimeInterval,
        now: Date
    ) -> [URL] {
        let canonicalDirectory = canonical(serviceDirectory)
        let outstanding = Set(outstandingURLs.map(canonical))

        return files.compactMap { file in
            let canonicalURL = canonical(file.url)
            guard canonicalURL.deletingLastPathComponent() == canonicalDirectory,
                  canonicalURL.lastPathComponent.hasPrefix(filePrefix),
                  now.timeIntervalSince(file.modifiedAt) >= staleAge,
                  !outstanding.contains(canonicalURL) else {
                return nil
            }
            return file.url
        }
    }

    private static func canonical(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
}
