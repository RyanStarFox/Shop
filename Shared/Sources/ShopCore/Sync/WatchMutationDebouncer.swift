import Foundation

@MainActor
public final class WatchMutationDebouncer {
    public typealias Sleep = @Sendable (TimeInterval) async -> Void

    private let delay: TimeInterval
    private let sleep: Sleep
    private var pendingTask: Task<Void, Never>?

    public init(
        delay: TimeInterval = 0.5,
        sleep: @escaping Sleep = WatchMutationDebouncer.defaultSleep
    ) {
        self.delay = delay
        self.sleep = sleep
    }

    deinit {
        pendingTask?.cancel()
    }

    public func schedule(
        _ operation: @escaping @MainActor @Sendable () -> Void
    ) {
        pendingTask?.cancel()
        let delay = self.delay
        let sleep = self.sleep
        pendingTask = Task { @MainActor [weak self] in
            await sleep(delay)
            guard !Task.isCancelled, let self else { return }
            self.pendingTask = nil
            operation()
        }
    }

    public func cancel() {
        pendingTask?.cancel()
        pendingTask = nil
    }

    public static func defaultSleep(_ interval: TimeInterval) async {
        try? await Task.sleep(for: .seconds(interval))
    }
}
