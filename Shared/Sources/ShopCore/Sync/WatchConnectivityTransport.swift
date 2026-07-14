import Foundation

#if os(iOS) || os(watchOS)
import WatchConnectivity

@MainActor
public final class WatchConnectivityTransport: NSObject, ObservableObject {
    @Published public private(set) var isReachable = false
    @Published public private(set) var isSyncing = false
    @Published public private(set) var lastSyncDate: Date?
    @Published public private(set) var lastError: String?

    /// WatchConnectivity documents this callback for one reply from any queue.
    /// The wrapper makes that framework-owned thread-safe callback explicit at
    /// the actor hop without treating the whole framework as pre-concurrency.
    private struct ReplyHandler: @unchecked Sendable {
        let send: ([String: Any]) -> Void
    }

    private enum FileReadResult: Sendable {
        case success(Data)
        case failure(String)
    }

    private static let applicationContextBudget = 60_000
    private static let immediateReplyBudget = 50_000
    private static let temporaryFilePrefix = "shop-watch-snapshot-"
    private static let staleFileAge: TimeInterval = 24 * 60 * 60
    private static let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("shop-watch-sync", isDirectory: true)
    private let mutationDebouncer = WatchMutationDebouncer()
    private var dataStore: DataStore?
    private var localMutationObserverID: UUID?

    public override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        cleanStaleTemporaryFiles(
            outstandingURLs: session.outstandingFileTransfers.map(
                \.file.fileURL
            )
        )
        session.delegate = self
        session.activate()
    }

    isolated deinit {
        mutationDebouncer.cancel()
        if let dataStore, let localMutationObserverID {
            dataStore.removeLocalMutationObserver(localMutationObserverID)
        }
    }

    public func configure(with dataStore: DataStore) {
        guard self.dataStore !== dataStore else { return }
        mutationDebouncer.cancel()
        if let currentStore = self.dataStore, let localMutationObserverID {
            currentStore.removeLocalMutationObserver(localMutationObserverID)
        }
        self.dataStore = dataStore
        localMutationObserverID = dataStore.addLocalMutationObserver { [weak self] in
            self?.scheduleMutationSync()
        }
    }

    private func scheduleMutationSync() {
        mutationDebouncer.schedule { [weak self] in
            self?.sendLatestSnapshot()
        }
    }

    public func sendLatestSnapshot() {
        mutationDebouncer.cancel()
        guard let data = encodedSnapshot() else { return }
        publishLatestSnapshot(data)

        guard WCSession.default.isReachable,
              data.count <= Self.immediateReplyBudget else {
            return
        }
        isSyncing = true
        WCSession.default.sendMessage(
            WatchMessageProtocol.makeSnapshotMessage(data),
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
            WatchMessageProtocol.makeRequest(),
            replyHandler: { [weak self] reply in
                let result = Result {
                    try WatchMessageProtocol.parseSnapshotReply(reply)
                }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch result {
                    case .success(.snapshot(let data)):
                        self.handleReceivedSnapshot(data)
                    case .success(.deferred):
                        break
                    case .failure(let error):
                        self.lastError = error.localizedDescription
                    }
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
            try WCSession.default.updateApplicationContext(
                [WatchMessageProtocol.snapshotKey: data]
            )
        } catch {
            lastError = error.localizedDescription
            transferSnapshotFile(data)
        }
    }

    private func transferSnapshotFile(_ data: Data) {
        let url = Self.temporaryDirectory
            .appendingPathComponent(
                "\(Self.temporaryFilePrefix)\(UUID().uuidString).json"
            )
        do {
            try FileManager.default.createDirectory(
                at: Self.temporaryDirectory,
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
            WCSession.default.transferFile(
                url,
                metadata: [
                    WatchMessageProtocol.actionKey:
                        WatchMessageProtocol.snapshotAction
                ]
            )
        } catch {
            let transferError = error.localizedDescription
            do {
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
                lastError = transferError
            } catch {
                lastError = [
                    transferError,
                    ShopStrings.watchFileCleanupFailed(error.localizedDescription)
                ].joined(separator: " ")
            }
        }
    }

    private func cleanStaleTemporaryFiles(
        outstandingURLs: [URL],
        now: Date = Date()
    ) {
        do {
            guard FileManager.default.fileExists(
                atPath: Self.temporaryDirectory.path
            ) else {
                return
            }
            let urls = try FileManager.default.contentsOfDirectory(
                at: Self.temporaryDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            let records = try urls.map { url in
                let values = try url.resourceValues(
                    forKeys: [.contentModificationDateKey]
                )
                return WatchTemporaryFileRecord(
                    url: url,
                    modifiedAt: values.contentModificationDate ?? now
                )
            }
            let candidates = WatchTemporaryFileCleanup.candidates(
                from: records,
                outstandingURLs: outstandingURLs,
                serviceDirectory: Self.temporaryDirectory,
                filePrefix: Self.temporaryFilePrefix,
                olderThan: Self.staleFileAge,
                now: now
            )
            for url in candidates {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            lastError = ShopStrings.watchFileCleanupFailed(
                error.localizedDescription
            )
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
        let outstandingURLs = session.outstandingFileTransfers.map(
            \.file.fileURL
        )
        Task { @MainActor [weak self] in
            self?.cleanStaleTemporaryFiles(
                outstandingURLs: outstandingURLs
            )
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
        let action = message[WatchMessageProtocol.actionKey] as? String
        let data = message[WatchMessageProtocol.snapshotKey] as? Data
        Task { @MainActor [weak self] in
            guard let self else { return }
            if action == WatchMessageProtocol.requestSnapshotAction {
                self.sendLatestSnapshot()
            } else if action == WatchMessageProtocol.snapshotAction, let data {
                self.handleReceivedSnapshot(data)
            }
        }
    }

    public nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        let action = message[WatchMessageProtocol.actionKey] as? String
        let data = message[WatchMessageProtocol.snapshotKey] as? Data
        let reply = ReplyHandler(send: replyHandler)
        Task { @MainActor [weak self] in
            guard let self else { return }
            if action == WatchMessageProtocol.requestSnapshotAction {
                self.mutationDebouncer.cancel()
                guard let snapshot = self.encodedSnapshot() else {
                    reply.send(WatchMessageProtocol.makeDeferredReply())
                    return
                }
                reply.send(
                    WatchMessageProtocol.makeSnapshotReply(
                        snapshot,
                        safeByteLimit: Self.immediateReplyBudget
                    )
                )
                self.publishLatestSnapshot(snapshot)
            } else if action == WatchMessageProtocol.snapshotAction, let data {
                reply.send(WatchMessageProtocol.makeAcknowledgement())
                self.handleReceivedSnapshot(data)
            } else {
                reply.send([:])
            }
        }
    }

    public nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        let data = applicationContext[WatchMessageProtocol.snapshotKey] as? Data
        Task { @MainActor [weak self] in
            guard let data else { return }
            self?.handleReceivedSnapshot(data)
        }
    }

    public nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let result: FileReadResult
        do {
            result = .success(try Data(contentsOf: file.fileURL))
        } catch {
            result = .failure(error.localizedDescription)
        }
        Task { @MainActor [weak self] in
            switch result {
            case .success(let data):
                self?.handleReceivedSnapshot(data)
            case .failure(let detail):
                self?.lastError = ShopStrings.watchFileReadFailed(detail)
            }
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
            if let errorDescription {
                self?.lastError = errorDescription
            }
            do {
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
            } catch {
                self?.lastError = ShopStrings.watchFileCleanupFailed(
                    error.localizedDescription
                )
            }
        }
    }
}

public typealias WatchSyncService = WatchConnectivityTransport
#endif
