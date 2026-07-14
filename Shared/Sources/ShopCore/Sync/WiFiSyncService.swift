import Foundation

#if os(iOS) || os(watchOS)
import WatchConnectivity

@MainActor
public final class WiFiSyncService: NSObject, ObservableObject {
    @Published public var isReachable = false
    @Published public var isSyncing = false
    @Published public var lastSyncDate: Date?

    private var dataStore: DataStore?
    private var pendingMessages: [Data] = []

    public override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    public func configure(with dataStore: DataStore) {
        self.dataStore = dataStore
    }

    public func requestSync() {
        guard WCSession.default.isReachable else { return }
        sendMessage(["action": "requestSync"])
    }

    public func pushData() {
        guard WCSession.default.isReachable, let data = dataStore?.exportData() else {
            // Store for later delivery
            if let data = dataStore?.exportData() {
                pendingMessages.append(data)
            }
            return
        }
        isSyncing = true
        let message: [String: Any] = [
            "action": "syncData",
            "payload": data,
            "timestamp": Date().timeIntervalSince1970
        ]
        WCSession.default.sendMessage(message, replyHandler: { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isSyncing = false
                self?.lastSyncDate = Date()
            }
        }, errorHandler: { [weak self] error in
            let errorDescription = String(describing: error)
            Task { @MainActor [weak self] in
                print("WiFi sync failed: \(errorDescription)")
                self?.isSyncing = false
            }
        })
    }

    private func sendMessage(_ dict: [String: Any]) {
        WCSession.default.sendMessage(dict, replyHandler: nil) { error in
            print("Message failed: \(error)")
        }
    }

    private func handleReachabilityChange(_ reachable: Bool) {
        isReachable = reachable
        guard reachable, !pendingMessages.isEmpty else { return }

        let messages = pendingMessages
        pendingMessages.removeAll()
        for message in messages {
            WCSession.default.sendMessage(
                [
                    "action": "syncData",
                    "payload": message,
                    "timestamp": Date().timeIntervalSince1970
                ],
                replyHandler: nil
            )
        }
    }
}

extension WiFiSyncService: WCSessionDelegate {
    public nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith state: WCSessionActivationState,
        error: Error?
    ) {
        let reachable = session.isReachable
        let errorDescription = error.map { String(describing: $0) }
        Task { @MainActor [weak self] in
            if let errorDescription {
                print("WCSession activation failed: \(errorDescription)")
            }
            self?.handleReachabilityChange(reachable)
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

    public nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let action = message["action"] as? String else { return }
        let payload = (message["payload"] as? Data).map { Data($0) }
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch action {
            case "requestSync":
                pushData()
            case "syncData":
                if let payload {
                    dataStore?.importData(payload)
                    lastSyncDate = Date()
                }
            default:
                break
            }
        }
    }

    public nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        let data = Data(messageData)
        Task { @MainActor [weak self] in
            self?.dataStore?.importData(data)
            self?.lastSyncDate = Date()
        }
    }
}
#endif
