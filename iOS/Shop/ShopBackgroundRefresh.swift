import Foundation
import BackgroundTasks
import WidgetKit
import ShopCore

@MainActor
final class ShopBackgroundSyncRunner {
    static let shared = ShopBackgroundSyncRunner()

    private weak var dataStore: DataStore?
    private weak var syncCoordinator: SyncCoordinator?

    func configure(dataStore: DataStore, syncCoordinator: SyncCoordinator) {
        self.dataStore = dataStore
        self.syncCoordinator = syncCoordinator
    }

    @discardableResult
    func run(clearNeedsSyncOnSuccess: Bool) async -> Bool {
        guard let dataStore, let syncCoordinator else { return false }
        dataStore.applyPendingWidgetMutations()
        await syncCoordinator.syncNowIfConfigured()
        dataStore.publishWidgetSnapshot()
        WidgetCenter.shared.reloadAllTimelines()
        if clearNeedsSyncOnSuccess, syncCoordinator.status.failureMessage == nil {
            WidgetSnapshotStore.clearNeedsSync()
        }
        return syncCoordinator.status.failureMessage == nil
    }
}

enum ShopBackgroundRefresh {
    static let taskID = "com.ryanstarfox.shop.refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            let taskBox = UncheckedTaskBox(refresh)
            refresh.expirationHandler = {
                taskBox.value.setTaskCompleted(success: false)
            }
            Task {
                let success = await ShopBackgroundSyncRunner.shared.run(clearNeedsSyncOnSuccess: true)
                taskBox.value.setTaskCompleted(success: success)
                ShopBackgroundRefresh.schedule()
            }
        }
    }

    static func schedule(earliest: Date = BackgroundSyncSchedule.nextEarliestBeginDate()) {
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = earliest
        try? BGTaskScheduler.shared.submit(request)
    }

    static func scheduleSoon() {
        schedule(earliest: Date())
    }
}

/// BGAppRefreshTask is not Sendable; box it for unstructured Task completion.
private final class UncheckedTaskBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
