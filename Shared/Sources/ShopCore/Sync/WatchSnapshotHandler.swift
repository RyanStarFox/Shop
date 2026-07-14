import Foundation

public enum WatchSnapshotHandlerError: Error, Equatable, Sendable {
    case invalidSnapshot
}

/// Platform-independent receive path for WatchConnectivity snapshots.
public struct WatchSnapshotHandler: Sendable {
    public init() {}

    public func handleReceivedSnapshot(
        _ data: Data,
        localSnapshot: SyncSnapshot
    ) throws -> SyncSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let remoteSnapshot = try decoder.decode(SyncSnapshot.self, from: data)
            return SnapshotMerger().merge(local: localSnapshot, remote: remoteSnapshot)
        } catch {
            throw WatchSnapshotHandlerError.invalidSnapshot
        }
    }
}
