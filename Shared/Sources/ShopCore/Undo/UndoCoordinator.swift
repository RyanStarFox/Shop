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
    public typealias MutationPerformer = (@MainActor () throws -> Void) throws -> Void

    @Published public private(set) var undoStack: [UndoAction] = []

    public var currentAction: UndoAction? { undoStack.last }
    public var canUndo: Bool { !undoStack.isEmpty }

    private let maxHistoryCount: Int
    private let performMutation: MutationPerformer

    public init(
        maxHistoryCount: Int = 50,
        performMutation: @escaping MutationPerformer = { try $0() }
    ) {
        self.maxHistoryCount = max(1, maxHistoryCount)
        self.performMutation = performMutation
    }

    public func present(_ action: UndoAction) {
        undoStack.append(action)
        if undoStack.count > maxHistoryCount {
            undoStack.removeFirst(undoStack.count - maxHistoryCount)
        }
    }

    public func dismiss() {
        guard !undoStack.isEmpty else { return }
        undoStack.removeLast()
    }

    public func undo() throws {
        guard let action = undoStack.last else { return }
        do {
            try performMutation(action.perform)
            undoStack.removeLast()
        } catch {
            throw error
        }
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

    public static func undoBatchCompletion(
        previousStates: [(itemID: UUID, isCompleted: Bool, completedAt: Date?)],
        store: ShoppingStore,
        now: Date = Date()
    ) -> UndoAction {
        UndoAction(message: ShopStrings.undoBatchItemsChanged) {
            try store.restoreCompletionStates(previousStates, now: now)
        }
    }

    public static func undoBatchItemDelete(
        itemIDs: [UUID],
        store: ShoppingStore,
        now: Date = Date()
    ) -> UndoAction {
        UndoAction(message: ShopStrings.undoBatchItemsDeleted) {
            try store.restoreItems(itemIDs: itemIDs, now: now)
        }
    }

    public static func undoBatchTagMembership(
        previousMemberships: [(itemID: UUID, tagIDs: [UUID])],
        store: ShoppingStore,
        now: Date = Date()
    ) -> UndoAction {
        UndoAction(message: ShopStrings.undoBatchTagsChanged) {
            try store.restoreTagMemberships(previousMemberships, now: now)
        }
    }

    public static func undoItemEdit(
        itemID: UUID,
        previousName: String,
        previousTagIDs: [UUID],
        previousCreatedAt: Date,
        previousIsCompleted: Bool,
        previousCompletedAt: Date?,
        store: ShoppingStore,
        now: Date = Date()
    ) -> UndoAction {
        UndoAction(message: ShopStrings.undoItemEdited) {
            try store.restoreItemFields(
                itemID: itemID,
                name: previousName,
                tagIDs: previousTagIDs,
                createdAt: previousCreatedAt,
                isCompleted: previousIsCompleted,
                completedAt: previousCompletedAt,
                now: now
            )
        }
    }
}