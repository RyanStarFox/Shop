import Foundation

public enum WatchSnapshotHandlerError: Error, Equatable, LocalizedError, Sendable {
    case invalidSnapshot
    case unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidSnapshot:
            ShopStrings.watchInvalidSnapshot
        case .unsupportedVersion(let version):
            ShopStrings.watchUnsupportedSnapshotVersion(version)
        }
    }
}

/// Platform-independent receive path for WatchConnectivity snapshots.
public struct WatchSnapshotHandler: Sendable {
    private struct VersionEnvelope: Decodable {
        let version: Int?
    }

    public init() {}

    public func handleReceivedSnapshot(
        _ data: Data,
        localSnapshot: SyncSnapshot
    ) throws -> SyncSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let envelope = try decoder.decode(VersionEnvelope.self, from: data)
            let version = envelope.version ?? 1
            guard (1...SyncSnapshot.currentVersion).contains(version) else {
                throw WatchSnapshotHandlerError.unsupportedVersion(version)
            }
            let remoteSnapshot = try decoder.decode(SyncSnapshot.self, from: data)
            return SnapshotMerger().merge(local: localSnapshot, remote: remoteSnapshot)
        } catch let error as WatchSnapshotHandlerError {
            throw error
        } catch {
            throw WatchSnapshotHandlerError.invalidSnapshot
        }
    }
}
