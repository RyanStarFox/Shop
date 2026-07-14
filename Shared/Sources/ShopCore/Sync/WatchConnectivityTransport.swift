import Foundation

#if os(iOS) || os(watchOS)
import WatchConnectivity

@MainActor
public final class WatchConnectivityTransport: NSObject, ObservableObject {
    @Published public private(set) var isReachable = false
    @Published public private(set) var isSyncing = false
    @Published public private(set) var lastSyncDate: Date?
    @Published public private(set) var lastError: String?

    private enum MessageKey {
        static let action = "action"
        static let snapshot = "snapshot"
        static let request = "requestSnapshot"
        static let reply = "reply"
    }

    private static let applicationContextBudget = 60_000
    private var dataStore: DataStore?

    public override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    public func configure(with dataStore: DataStore) {
        guard self.dataStore !== dataStore else { return }
        self.dataStore = dataStore
        dataStore.addLocalMutationObserver { [weak self] in
            self?.sendLatestSnapshot()
        }
    }

    public func sendLatestSnapshot() {
        guard let data = encodedSnapshot() else { return }
        publishLatestSnapshot(data)

        guard WCSession.default.isReachable else { return }
        isSyncing = true
        WCSession.default.sendMessage(
            [MessageKey.action: MessageKey.snapshot, MessageKey.snapshot: data],
            replyHandler: { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.isSyncing = false
                    self?.lastSyncDate = Date()
                }
            },
            errorHandler: { [weak self] error in
                let description = error.localizedDescription
                Task { @MainActor [weak self] in
                    self?.isSyncing = false
                    self?.lastError = description
                }
            }
        )
    }

    public func requestLatestSnapshot() {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(
            [MessageKey.action: MessageKey.request],
            replyHandler: { [weak self] reply in
                let data = reply[MessageKey.snapshot] as? Data
                Task { @MainActor [weak self] in
                    guard let data else { return }
                    self?.handleReceivedSnapshot(data)
                }
            },
            errorHandler: { [weak self] error in
                let description = error.localizedDescription
                Task { @MainActor [weak self] in
                    self?.lastError = description
                }
            }
        )
    }

    public func handleReceivedSnapshot(_ data: Data) {
        guard let dataStore else { return }
        do {
            let local = try dataStore.shoppingStore.makeSnapshot()
            let merged = try WatchSnapshotHandler().handleReceivedSnapshot(
                data,
                localSnapshot: local
            )
            dataStore.applyRemoteSnapshot(merged)
            lastSyncDate = Date()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func encodedSnapshot() -> Data? {
        guard let dataStore else { return nil }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            return try encoder.encode(dataStore.shoppingStore.makeSnapshot())
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    private func publishLatestSnapshot(_ data: Data) {
        if data.count >= Self.applicationContextBudget {
            transferSnapshotFile(data)
            return
        }
        do {
            try WCSession.default.updateApplicationContext([MessageKey.snapshot: data])
        } catch {
            lastError = error.localizedDescription
            transferSnapshotFile(data)
        }
    }

    private func transferSnapshotFile(_ data: Data) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("shop-watch-snapshot-\(UUID().uuidString).json")
        do {
            try data.write(to: url, options: .atomic)
            WCSession.default.transferFile(url, metadata: [MessageKey.action: MessageKey.snapshot])
        } catch {
            try? FileManager.default.removeItem(at: url)
            lastError = error.localizedDescription
        }
    }

    private func handleReachabilityChange(_ reachable: Bool) {
        isReachable = reachable
        guard reachable else { return }
        requestLatestSnapshot()
        sendLatestSnapshot()
    }
}

extension WatchConnectivityTransport: WCSessionDelegate {
    public nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith state: WCSessionActivationState,
        error: Error?
    ) {
        let reachable = session.isReachable
        let errorDescription = error?.localizedDescription
        Task { @MainActor [weak self] in
            self?.isReachable = reachable
            if let errorDescription {
                self?.lastError = errorDescription
            } else {
                self?.requestLatestSnapshot()
                self?.sendLatestSnapshot()
            }
        }
    }

    #if os(iOS)
    public nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    public nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor in
            WCSession.default.activate()
        }
    }
    #endif

    public nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor [weak self] in
            self?.handleReachabilityChange(reachable)
        }
    }

    public nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        let action = message[MessageKey.action] as? String
        let data = message[MessageKey.snapshot] as? Data
        Task { @MainActor [weak self] in
            guard let self else { return }
            if action == MessageKey.request {
                self.sendLatestSnapshot()
            } else if action == MessageKey.snapshot, let data {
                self.handleReceivedSnapshot(data)
            }
        }
    }

    public nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        let action = message[MessageKey.action] as? String
        let data = message[MessageKey.snapshot] as? Data
        replyHandler([MessageKey.reply: true])
        Task { @MainActor [weak self] in
            guard let self else { return }
            if action == MessageKey.request {
                self.sendLatestSnapshot()
            } else if action == MessageKey.snapshot, let data {
                self.handleReceivedSnapshot(data)
            }
        }
    }

    public nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        let data = applicationContext[MessageKey.snapshot] as? Data
        Task { @MainActor [weak self] in
            guard let data else { return }
            self?.handleReceivedSnapshot(data)
        }
    }

    public nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let data = try? Data(contentsOf: file.fileURL)
        Task { @MainActor [weak self] in
            guard let data else { return }
            self?.handleReceivedSnapshot(data)
        }
    }

    public nonisolated func session(
        _ session: WCSession,
        didFinish fileTransfer: WCSessionFileTransfer,
        error: Error?
    ) {
        let url = fileTransfer.file.fileURL
        let errorDescription = error?.localizedDescription
        Task { @MainActor [weak self] in
            try? FileManager.default.removeItem(at: url)
            if let errorDescription {
                self?.lastError = errorDescription
            }
        }
    }
}

public typealias WatchSyncService = WatchConnectivityTransport
#endif
