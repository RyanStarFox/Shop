import Foundation
import WatchConnectivity

#if os(iOS) || os(watchOS)
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
            self?.isSyncing = false
            self?.lastSyncDate = Date()
        }, errorHandler: { [weak self] error in
            print("WiFi sync failed: \(error)")
            self?.isSyncing = false
        })
    }

    private func sendMessage(_ dict: [String: Any]) {
        WCSession.default.sendMessage(dict, replyHandler: nil) { error in
            print("Message failed: \(error)")
        }
    }
}

extension WiFiSyncService: WCSessionDelegate {
    public func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("WCSession activation failed: \(error)")
        }
        isReachable = session.isReachable
    }

    #if os(iOS)
    public func sessionDidBecomeInactive(_ session: WCSession) {}
    public func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif

    public func sessionReachabilityDidChange(_ session: WCSession) {
        isReachable = session.isReachable
        if isReachable, !pendingMessages.isEmpty {
            for message in pendingMessages where session.isReachable {
                session.sendMessage(["action": "syncData", "payload": message, "timestamp": Date().timeIntervalSince1970], replyHandler: nil)
            }
            pendingMessages.removeAll()
        }
    }

    public func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let action = message["action"] as? String else { return }
        switch action {
        case "requestSync":
            pushData()
        case "syncData":
            if let payload = message["payload"] as? Data {
                dataStore?.importData(payload)
                lastSyncDate = Date()
            }
        default:
            break
        }
    }

    public func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        dataStore?.importData(messageData)
        lastSyncDate = Date()
    }
}
#endif
