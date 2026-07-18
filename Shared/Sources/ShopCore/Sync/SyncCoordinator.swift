import Combine
import Foundation

public enum SyncStatus: Equatable, Sendable {
    case idle(lastSuccess: Date?)
    case syncing
    case failed(message: String, canRetry: Bool)

    public var isSyncing: Bool {
        self == .syncing
    }

    public var lastSuccess: Date? {
        guard case let .idle(lastSuccess) = self else { return nil }
        return lastSuccess
    }

    public var failureMessage: String? {
        guard case let .failed(message, _) = self else { return nil }
        return message
    }
}

@MainActor
public final class SyncCoordinator: ObservableObject {
    public typealias Sleep = @Sendable (TimeInterval) async -> Void

    @Published public private(set) var status: SyncStatus

    public var lastSuccess: Date? {
        status.lastSuccess
    }

    private let dataStore: DataStore
    private let now: () -> Date
    private let sleep: Sleep
    private var transport: (any WebDAVTransporting)?
    private var debounceTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
    private var debounceGeneration = 0
    private var needsAnotherPass = false

    public init(
        dataStore: DataStore,
        transport: (any WebDAVTransporting)? = nil,
        now: @escaping () -> Date = Date.init,
        sleep: @escaping Sleep = SyncCoordinator.sleepForDebounce
    ) {
        self.dataStore = dataStore
        self.transport = transport
        self.now = now
        self.sleep = sleep
        status = .idle(lastSuccess: nil)
        dataStore.addLocalMutationObserver { [weak self] in
            self?.scheduleSync()
        }
    }

    public func configure(transport: (any WebDAVTransporting)?) {
        self.transport = transport
    }

    public func scheduleSync() {
        guard transport != nil else { return }

        if syncTask != nil {
            needsAnotherPass = true
            return
        }

        debounceTask?.cancel()
        debounceGeneration += 1
        let generation = debounceGeneration
        debounceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.sleep(2)
            guard !Task.isCancelled, generation == self.debounceGeneration else { return }
            self.debounceTask = nil
            await self.beginSync(reportMissingTransport: false)
        }
    }

    public func syncNow() async {
        await syncNow(reportMissingTransport: true)
    }

    /// Sync immediately when a transport is configured; no-op (no error banner) otherwise.
    public func syncNowIfConfigured() async {
        await syncNow(reportMissingTransport: false)
    }

    private func syncNow(reportMissingTransport: Bool) async {
        if let debounceTask {
            debounceGeneration += 1
            debounceTask.cancel()
            self.debounceTask = nil
            await debounceTask.value
        }

        if let syncTask {
            needsAnotherPass = true
            await syncTask.value
            return
        }

        await beginSync(reportMissingTransport: reportMissingTransport)
    }

    private func beginSync(reportMissingTransport: Bool) async {
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runSyncPasses(reportMissingTransport: reportMissingTransport)
        }
        syncTask = task
        await task.value
    }

    private func runSyncPasses(reportMissingTransport: Bool) async {
        defer { syncTask = nil }
        repeat {
            needsAnotherPass = false
            await syncOnce(reportMissingTransport: reportMissingTransport)
        } while needsAnotherPass
    }

    private func syncOnce(reportMissingTransport: Bool) async {
        guard let transport else {
            if reportMissingTransport {
                status = .failed(message: ShopStrings.webdavNotConfigured, canRetry: false)
            }
            return
        }

        status = .syncing
        do {
            for attempt in 0..<3 {
                let remote = try await transport.fetch()
                let snapshot = try mergedSnapshot(with: remote)
                let precondition = try precondition(for: remote)
                do {
                    _ = try await transport.put(snapshot, precondition: precondition)
                    status = .idle(lastSuccess: now())
                    return
                } catch WebDAVError.preconditionFailed where attempt < 2 {
                    continue
                }
            }
            status = .failed(
                message: localizedMessage(for: WebDAVError.preconditionFailed),
                canRetry: true
            )
        } catch {
            status = .failed(message: localizedMessage(for: error), canRetry: isRetryable(error))
        }
    }

    private func mergedSnapshot(with remote: RemoteSnapshot?) throws -> SyncSnapshot {
        guard let remote else {
            return try dataStore.shoppingStore.makeSnapshot(now: now())
        }
        let local = try dataStore.shoppingStore.makeSnapshot(now: now())
        let merged = SnapshotMerger().merge(local: local, remote: remote.snapshot)
        // Apply the already-merged snapshot directly — do not merge again inside apply().
        try dataStore.shoppingStore.applyCanonicalSnapshot(merged)
        dataStore.fetchData()
        dataStore.publishWidgetSnapshot()
        return try dataStore.shoppingStore.makeSnapshot(now: now())
    }

    private func precondition(for remote: RemoteSnapshot?) throws -> WebDAVPrecondition {
        guard let remote else {
            return .create
        }
        guard let etag = remote.etag else {
            throw WebDAVError.invalidResponse
        }
        return .etag(etag)
    }

    private func localizedMessage(for error: Error) -> String {
        var message: String
        if let error = error as? WebDAVError {
            message = error.userFacingMessage
        } else {
            message = """
            \(ShopStrings.webdavSyncFailed)
            \(ShopStrings.webdavErrorDetailPrefix)\(error.localizedDescription)
            """
        }
        if let url = transport?.diagnosticFileURL {
            message += "\n\(ShopStrings.webdavTargetURLPrefix)\(url)"
        }
        return message
    }

    private func isRetryable(_ error: Error) -> Bool {
        (error as? WebDAVError)?.isRecoverable ?? true
    }

    public static func sleepForDebounce(_ interval: TimeInterval) async {
        try? await Task.sleep(for: .seconds(interval))
    }
}
