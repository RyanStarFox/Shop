import Combine
import Foundation

public struct UndoAction: Identifiable {
    public let id: UUID
    public let message: String
    public let perform: @MainActor () throws -> Void

    public init(
        id: UUID = UUID(),
        message: String,
        perform: @escaping @MainActor () throws -> Void
    ) {
        self.id = id
        self.message = message
        self.perform = perform
    }
}

@MainActor
public final class UndoCoordinator: ObservableObject {
    public typealias Sleep = @Sendable (TimeInterval) async -> Void
    public typealias MutationPerformer = (@MainActor () throws -> Void) throws -> Void

    @Published public private(set) var currentAction: UndoAction?

    private let duration: TimeInterval
    private let sleep: Sleep
    private let performMutation: MutationPerformer
    private var expiryGeneration = 0

    public init(
        duration: TimeInterval = 5,
        sleep: @escaping Sleep = UndoCoordinator.defaultSleep,
        performMutation: @escaping MutationPerformer = { try $0() }
    ) {
        self.duration = duration
        self.sleep = sleep
        self.performMutation = performMutation
    }

    public func present(_ action: UndoAction) {
        expiryGeneration += 1
        let generation = expiryGeneration
        currentAction = action

        let duration = self.duration
        let sleep = self.sleep
        Task { @MainActor [weak self] in
            await sleep(duration)
            guard let self, self.expiryGeneration == generation else {
                return
            }
            self.currentAction = nil
        }
    }

    public func dismiss() {
        expiryGeneration += 1
        currentAction = nil
    }

    public func undo() throws {
        guard let action = currentAction else { return }
        try performMutation(action.perform)
        dismiss()
    }

    public static func defaultSleep(_ interval: TimeInterval) async {
        try? await Task.sleep(for: .seconds(interval))
    }
}

public enum ShoppingUndo {
    public static func undoCompletion(
        itemID: UUID,
        previousIsCompleted: Bool,
        previousCompletedAt: Date?,
        store: ShoppingStore,
        now: Date = Date()
    ) -> UndoAction {
        UndoAction(
            message: previousIsCompleted
                ? ShopStrings.undoItemRestored
                : ShopStrings.undoItemCompleted
        ) {
            try store.restoreCompletionState(
                itemID: itemID,
                isCompleted: previousIsCompleted,
                completedAt: previousCompletedAt,
                now: now
            )
        }
    }

    public static func undoItemDelete(
        itemID: UUID,
        store: ShoppingStore,
        now: Date = Date()
    ) -> UndoAction {
        UndoAction(message: ShopStrings.undoItemDeleted) {
            try store.restoreItem(itemID: itemID, now: now)
        }
    }

    public static func undoTagDelete(
        tagID: UUID,
        linkedItemIDs: [UUID],
        store: ShoppingStore,
        now: Date = Date()
    ) -> UndoAction {
        UndoAction(message: ShopStrings.undoTagDeleted) {
            try store.restoreTag(
                id: tagID,
                linkedItemIDs: linkedItemIDs,
                now: now
            )
        }
    }
}
