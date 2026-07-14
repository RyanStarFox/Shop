import Foundation

public enum WatchSnapshotReply: Equatable, Sendable {
    case snapshot(Data)
    case deferred
}

public enum WatchMessageProtocolError: Error, Equatable, LocalizedError, Sendable {
    case invalidReply

    public var errorDescription: String? {
        ShopStrings.watchInvalidReply
    }
}

public enum WatchMessageProtocol {
    public static let actionKey = "action"
    public static let snapshotKey = "snapshot"
    public static let statusKey = "status"
    public static let requestSnapshotAction = "requestSnapshot"
    public static let snapshotAction = "snapshot"

    private static let snapshotStatus = "snapshot"
    private static let deferredStatus = "deferred"
    private static let receivedStatus = "received"

    public static func makeRequest() -> [String: Any] {
        [actionKey: requestSnapshotAction]
    }

    public static func makeSnapshotMessage(_ data: Data) -> [String: Any] {
        [actionKey: snapshotAction, snapshotKey: data]
    }

    public static func makeSnapshotReply(
        _ data: Data,
        safeByteLimit: Int
    ) -> [String: Any] {
        guard data.count <= safeByteLimit else {
            return makeDeferredReply()
        }
        return [statusKey: snapshotStatus, snapshotKey: data]
    }

    public static func makeDeferredReply() -> [String: Any] {
        [statusKey: deferredStatus]
    }

    public static func makeAcknowledgement() -> [String: Any] {
        [statusKey: receivedStatus]
    }

    public static func parseSnapshotReply(
        _ reply: [String: Any]
    ) throws -> WatchSnapshotReply {
        switch reply[statusKey] as? String {
        case snapshotStatus:
            guard let data = reply[snapshotKey] as? Data else {
                throw WatchMessageProtocolError.invalidReply
            }
            return .snapshot(data)
        case deferredStatus:
            return .deferred
        default:
            throw WatchMessageProtocolError.invalidReply
        }
    }
}
