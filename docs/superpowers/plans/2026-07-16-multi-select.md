# Multi-Select Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add multi-select and batch actions (complete, restore, tags, delete) on iPhone and Mac, with Mac Shift/Command selection semantics.

**Architecture:** Keep selection as view-local `Set<UUID>`. Add atomic batch mutations in `ShoppingStore`/`DataStore` with one overall undo action each. Share selection helpers and tag tri-state logic in ShopCore; platform views own UX chrome.

**Tech Stack:** SwiftUI, SwiftData, ShopCore package, XCTest.

## Global Constraints

- Min versions: iOS 18 / macOS 15 / watchOS 11; Watch is out of scope.
- Selection is view-local `Set<UUID>`; never persist or sync selection.
- Batch complete/restore are independent actions, never per-item toggle of mixed sets.
- Tag UI is tri-state: all / some / none; click all → remove, click some/none → add.
- Delete always confirms and shows count.
- One batch mutation → one `fetchData` / widget publish / sync schedule / undo action.
- Missing IDs are ignored; already-at-target items are no-ops.
- Mac keeps custom brand selection highlight; no system list selection chrome.
- Commits only when the user asks.

---

## File Structure

| Path | Responsibility |
|------|----------------|
| `Shared/.../Presentation/ItemSelection.swift` (new) | Visual-order range selection + tag tri-state helpers |
| `Shared/.../Storage/ShoppingStore.swift` | Atomic batch store mutations |
| `Shared/.../Storage/DataStore.swift` | Public batch APIs + undo presentation |
| `Shared/.../Undo/UndoCoordinator.swift` | Batch undo factories |
| `Shared/.../Localization/*` | Multi-select strings (en + zh-Hans) |
| `Shared/Tests/ShopCoreTests/ItemSelectionTests.swift` (new) | Selection/range/tri-state tests |
| `Shared/Tests/ShopCoreTests/DataStoreBatchTests.swift` (new) | Batch mutation + undo tests |
| `iOS/Shop/ContentView.swift` | Select mode entry, trailing toolbar, bottom bar host |
| `iOS/Shop/Views/ItemListView.swift` | Multi-select rows, long-press, disable swipe/edit |
| `iOS/Shop/Views/BatchActionBar.swift` (new) | iPhone bottom batch chrome + tag sheet |
| `macOS/ShopMac/ContentView.swift` | `selectedItemIDs`, Shift/⌘, batch detail panel |

---

### Task 1: Selection helpers + tag tri-state

**Files:**
- Create: `Shared/Sources/ShopCore/Presentation/ItemSelection.swift`
- Create: `Shared/Tests/ShopCoreTests/ItemSelectionTests.swift`

**Interfaces:**
- Produces:
  - `enum TagMembership: Equatable { case all, some, none }`
  - `ItemSelection.visualOrderedIDs(from: ItemListSections) -> [UUID]`
  - `ItemSelection.range(from:to:in:) -> [UUID]`
  - `ItemSelection.membership(of:tagID:in:) -> TagMembership`
  - `ItemSelection.prunedSelection(_:visibleIDs:) -> Set<UUID>`

- [ ] **Step 1: Write failing tests**

```swift
@MainActor
final class ItemSelectionTests: XCTestCase {
    func testVisualOrderFlattensGroupsThenArchive() {
        let sections = ItemListSections(
            activeIDs: [],
            archivedIDs: [UUID(uuidString: "00000000-0000-0000-0000-000000000003")!],
            activeGroups: [
                ItemListTagGroup(
                    id: "a",
                    title: "A",
                    itemIDs: [
                        UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                        UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
                    ]
                )
            ]
        )
        XCTAssertEqual(
            ItemSelection.visualOrderedIDs(from: sections).map(\.uuidString),
            [
                "00000000-0000-0000-0000-000000000001",
                "00000000-0000-0000-0000-000000000002",
                "00000000-0000-0000-0000-000000000003"
            ]
        )
    }

    func testRangeIsInclusiveAndOrderIndependent() {
        let order = [UUID(), UUID(), UUID(), UUID()]
        XCTAssertEqual(ItemSelection.range(from: order[3], to: order[1], in: order), Array(order[1...3]))
        XCTAssertEqual(ItemSelection.range(from: order[1], to: order[3], in: order), Array(order[1...3]))
    }

    func testMissingEndpointYieldsEmptyRange() {
        let order = [UUID(), UUID()]
        XCTAssertTrue(ItemSelection.range(from: UUID(), to: order[0], in: order).isEmpty)
    }

    func testTagMembershipTriState() {
        let tag = UUID()
        let other = UUID()
        let items: [(UUID, Set<UUID>)] = [
            (UUID(), [tag]),
            (UUID(), [tag, other]),
            (UUID(), [other])
        ]
        XCTAssertEqual(ItemSelection.membership(of: tag, in: items), .some)
        XCTAssertEqual(ItemSelection.membership(of: other, in: Array(items.prefix(2))), .all)
        XCTAssertEqual(ItemSelection.membership(of: UUID(), in: items), .none)
    }

    func testPruneRemovesInvisibleIDs() {
        let keep = UUID()
        let drop = UUID()
        XCTAssertEqual(
            ItemSelection.prunedSelection([keep, drop], visibleIDs: [keep]),
            [keep]
        )
    }
}
```

- [ ] **Step 2: Run tests — expect FAIL**

```bash
cd "/Users/wangshaoyan/code/shop!/Shared" && swift test --filter ItemSelectionTests
```

Expected: compile failure / `ItemSelection` not found.

- [ ] **Step 3: Implement helpers**

```swift
import Foundation

public enum TagMembership: Equatable, Sendable {
    case all
    case some
    case none
}

public enum ItemSelection {
    public static func visualOrderedIDs(from sections: ItemListSections) -> [UUID] {
        var ids: [UUID] = []
        if sections.isGrouped {
            for group in sections.activeGroups {
                ids.append(contentsOf: group.itemIDs)
            }
        } else {
            ids.append(contentsOf: sections.activeIDs)
        }
        ids.append(contentsOf: sections.archivedIDs)
        return ids
    }

    public static func range(from start: UUID, to end: UUID, in order: [UUID]) -> [UUID] {
        guard let i = order.firstIndex(of: start), let j = order.firstIndex(of: end) else {
            return []
        }
        let lower = min(i, j)
        let upper = max(i, j)
        return Array(order[lower...upper])
    }

    public static func membership(
        of tagID: UUID,
        in items: [(id: UUID, tagIDs: Set<UUID>)]
    ) -> TagMembership {
        guard !items.isEmpty else { return .none }
        let hits = items.filter { $0.tagIDs.contains(tagID) }.count
        if hits == 0 { return .none }
        if hits == items.count { return .all }
        return .some
    }

    public static func prunedSelection(_ selection: Set<UUID>, visibleIDs: Set<UUID>) -> Set<UUID> {
        selection.intersection(visibleIDs)
    }
}
```

If `ItemListTagGroup` lacks a public memberwise init used by tests, add:

```swift
public init(id: String, title: String, itemIDs: [UUID]) {
    self.id = id
    self.title = title
    self.itemIDs = itemIDs
}
```

and a public `ItemListSections` memberwise init if missing.

- [ ] **Step 4: Re-run tests — expect PASS**

```bash
cd "/Users/wangshaoyan/code/shop!/Shared" && swift test --filter ItemSelectionTests
```

---

### Task 2: ShoppingStore batch mutations

**Files:**
- Modify: `Shared/Sources/ShopCore/Storage/ShoppingStore.swift`
- Create: `Shared/Tests/ShopCoreTests/DataStoreBatchTests.swift` (store-level portion first; expand in Task 3)

**Interfaces:**
- Consumes: existing `item(id:)`, `activeTags(ids:)`, `advanceVersion`, `save`
- Produces:
  - `setCompleted(itemIDs:completed:now:) throws -> [UUID]` (changed IDs)
  - `softDeleteItems(itemIDs:now:) throws -> [UUID]`
  - `addTag(tagID:toItemIDs:now:) throws -> [UUID]`
  - `removeTag(tagID:fromItemIDs:now:) throws -> [UUID]`
  - Single `save()` per call; rollback all on failure

- [ ] **Step 1: Write failing store/DataStore tests (store via DataStore wrapper later; write intent here)**

In `DataStoreBatchTests.swift` start with ShoppingStore-focused cases using `ShoppingStore(inMemory:)` directly:

```swift
@MainActor
final class DataStoreBatchTests: XCTestCase {
    func testBatchCompleteSkipsAlreadyCompletedAndUsesOneSaveTimestamp() throws {
        let store = try ShoppingStore(inMemory: true, deviceID: "test")
        let a = try store.addItem(name: "A", tagIDs: [], now: .t0)
        let b = try store.addItem(name: "B", tagIDs: [], now: .t0)
        try store.setCompleted(itemID: a.id, completed: true, now: .t1)
        let changed = try store.setCompleted(
            itemIDs: [a.id, b.id, UUID()],
            completed: true,
            now: .t2
        )
        XCTAssertEqual(changed, [b.id])
        XCTAssertEqual(store.item(id: b.id)?.completedAt, .t2)
        XCTAssertEqual(store.item(id: a.id)?.completedAt, .t1)
    }

    func testBatchRestoreClearsCompletedAt() throws {
        let store = try ShoppingStore(inMemory: true, deviceID: "test")
        let a = try store.addItem(name: "A", tagIDs: [], now: .t0)
        try store.setCompleted(itemID: a.id, completed: true, now: .t1)
        let changed = try store.setCompleted(itemIDs: [a.id], completed: false, now: .t2)
        XCTAssertEqual(changed, [a.id])
        XCTAssertFalse(try XCTUnwrap(store.item(id: a.id)).isCompleted)
        XCTAssertNil(store.item(id: a.id)?.completedAt)
    }

    func testBatchDeleteIsSoftDelete() throws {
        let store = try ShoppingStore(inMemory: true, deviceID: "test")
        let a = try store.addItem(name: "A", tagIDs: [], now: .t0)
        let deleted = try store.softDeleteItems(itemIDs: [a.id], now: .t1)
        XCTAssertEqual(deleted, [a.id])
        XCTAssertTrue(store.activeItems.isEmpty)
        XCTAssertNotNil(store.item(id: a.id)?.deletedAt)
    }

    func testBatchAddAndRemoveTagTriStateSemantics() throws {
        let store = try ShoppingStore(inMemory: true, deviceID: "test")
        let tag = try store.addTag(name: "Food", colorHex: "#C53A32", now: .t0)
        let a = try store.addItem(name: "A", tagIDs: [tag.id], now: .t0)
        let b = try store.addItem(name: "B", tagIDs: [], now: .t0)
        let added = try store.addTag(tagID: tag.id, toItemIDs: [a.id, b.id], now: .t1)
        XCTAssertEqual(added, [b.id])
        let removed = try store.removeTag(tagID: tag.id, fromItemIDs: [a.id, b.id], now: .t2)
        XCTAssertEqual(Set(removed), [a.id, b.id])
    }
}
```

Reuse existing test date helpers (`.t0`, `.t1`, `.t2`) from other ShopCore tests; if private, duplicate minimal `Date` extensions in this file.

- [ ] **Step 2: Run — expect FAIL**

```bash
cd "/Users/wangshaoyan/code/shop!/Shared" && swift test --filter DataStoreBatchTests
```

- [ ] **Step 3: Implement ShoppingStore batch APIs**

```swift
@discardableResult
public func setCompleted(
    itemIDs: [UUID],
    completed: Bool,
    now: Date = Date()
) throws -> [UUID] {
    var changed: [UUID] = []
    var snapshots: [(ShoppingItem, Bool, Date?, Date, String)] = []
    for id in itemIDs {
        guard let item = item(id: id), item.deletedAt == nil else { continue }
        guard item.isCompleted != completed else { continue }
        snapshots.append((item, item.isCompleted, item.completedAt, item.updatedAt, item.lastEditorDeviceID))
        item.isCompleted = completed
        item.completedAt = completed ? now : nil
        advanceVersion(of: item, now: now)
        changed.append(id)
    }
    guard !changed.isEmpty else { return [] }
    do {
        try save()
    } catch {
        for (item, wasCompleted, completedAt, updatedAt, deviceID) in snapshots {
            item.isCompleted = wasCompleted
            item.completedAt = completedAt
            item.updatedAt = updatedAt
            item.lastEditorDeviceID = deviceID
        }
        modelContext.rollback()
        throw error
    }
    return changed
}

@discardableResult
public func softDeleteItems(itemIDs: [UUID], now: Date = Date()) throws -> [UUID] {
    // same snapshot/rollback pattern; set deletedAt = now; skip already deleted
}

@discardableResult
public func addTag(tagID: UUID, toItemIDs: [UUID], now: Date = Date()) throws -> [UUID] {
    let tag = try activeTags(ids: [tagID]).first!
    // for each item missing tag: item.tags.append(tag); advanceVersion; collect changed
    // one save + rollback
}

@discardableResult
public func removeTag(tagID: UUID, fromItemIDs: [UUID], now: Date = Date()) throws -> [UUID] {
    // remove matching tags; advanceVersion only when membership changed
}
```

Keep single-item `setCompleted` / `softDeleteItem` as wrappers calling the batch APIs with one ID, or leave them unchanged to minimize risk — prefer leaving single-item methods unchanged.

- [ ] **Step 4: Re-run — expect PASS**

```bash
cd "/Users/wangshaoyan/code/shop!/Shared" && swift test --filter DataStoreBatchTests
```

---

### Task 3: DataStore batch APIs + batch undo

**Files:**
- Modify: `Shared/Sources/ShopCore/Storage/DataStore.swift`
- Modify: `Shared/Sources/ShopCore/Undo/UndoCoordinator.swift` (`ShoppingUndo`)
- Modify: `Shared/Tests/ShopCoreTests/DataStoreBatchTests.swift`
- Modify: `Shared/Tests/ShopCoreTests/UndoCoordinatorTests.swift` (add batch undo case)

**Interfaces:**
- Consumes: Task 2 store APIs
- Produces:
  - `DataStore.setCompleted(itemIDs:completed:presentUndo:)`
  - `DataStore.deleteItems(itemIDs:presentUndo:)`
  - `DataStore.addTag(_:toItemIDs:presentUndo:)`
  - `DataStore.removeTag(_:fromItemIDs:presentUndo:)`
  - `ShoppingUndo.undoBatchCompletion(...)`
  - `ShoppingUndo.undoBatchItemDelete(...)`
  - `ShoppingUndo.undoBatchTagMembership(...)`
  - Exactly one mutation observer notification per successful batch

- [ ] **Step 1: Add failing DataStore/undo tests**

```swift
func testBatchCompletePresentsSingleUndoAndOneObserver() {
    let store = DataStore(inMemory: true)
    store.addItem(name: "A")
    store.addItem(name: "B")
    let ids = store.items.map(\.id)
    var undos = 0
    var observers = 0
    _ = store.addLocalMutationObserver { observers += 1 }
    observers = 0
    store.setCompleted(ids, completed: true) { _ in undos += 1 }
    XCTAssertEqual(undos, 1)
    XCTAssertEqual(observers, 1)
    XCTAssertEqual(store.activeItems.count, 0)
}

func testBatchDeleteUndoRestoresAll() throws {
    // present delete undo, call coordinator.undo(), assert both restored
}

func testBatchTagAddUndoRestoresMembership() throws {
    // add tag to two items via batch; undo restores prior membership
}
```

- [ ] **Step 2: Run — expect FAIL**

```bash
cd "/Users/wangshaoyan/code/shop!/Shared" && swift test --filter DataStoreBatchTests
```

- [ ] **Step 3: Implement undo factories**

```swift
public static func undoBatchCompletion(
    previousStates: [(itemID: UUID, isCompleted: Bool, completedAt: Date?)],
    store: ShoppingStore,
    now: Date = Date()
) -> UndoAction {
    UndoAction(message: ShopStrings.undoBatchItemsChanged) {
        for state in previousStates {
            try store.restoreCompletionState(
                itemID: state.itemID,
                isCompleted: state.isCompleted,
                completedAt: state.completedAt,
                now: now
            )
        }
    }
}
```

Note: `restoreCompletionState` currently saves per item. For true atomic undo, either:
1. Add `restoreCompletionStates(_:now:)` batch restore with one save (preferred), or
2. Accept multiple saves inside undo perform but still one `UndoAction`.

Prefer (1): add `restoreCompletionStates`, `restoreItems`, and `restoreTagMemberships` batch helpers used only by undo.

- [ ] **Step 4: Implement DataStore wrappers**

```swift
public func setCompleted(
    _ itemIDs: [UUID],
    completed: Bool,
    presentUndo: (UndoAction) -> Void
) {
    let previous: [(UUID, Bool, Date?)] = itemIDs.compactMap { id in
        guard let item = items.first(where: { $0.id == id }) else { return nil }
        guard item.isCompleted != completed else { return nil }
        return (id, item.isCompleted, item.completedAt)
    }
    let succeeded = performMutation {
        _ = try shoppingStore.setCompleted(itemIDs: itemIDs, completed: completed)
    }
    guard succeeded, !previous.isEmpty else { return }
    presentUndo(
        ShoppingUndo.undoBatchCompletion(
            previousStates: previous.map { ($0.0, $0.1, $0.2) },
            store: shoppingStore
        )
    )
}
```

Mirror for `deleteItems`, `addTag(_:toItemIDs:)`, `removeTag(_:fromItemIDs:)`. Capture previous tag ID sets before mutation for tag undo.

- [ ] **Step 5: Re-run — expect PASS**

```bash
cd "/Users/wangshaoyan/code/shop!/Shared" && swift test --filter DataStoreBatchTests --filter UndoCoordinatorTests
```

---

### Task 4: Localization strings

**Files:**
- Modify: `Shared/Sources/ShopCore/Localization/Strings.swift`
- Modify: `Shared/Sources/ShopCore/Resources/en.lproj/Localizable.strings`
- Modify: `Shared/Sources/ShopCore/Resources/zh-Hans.lproj/Localizable.strings`
- Modify if present: `macOS/ShopMac/en.lproj/Localizable.strings`, `macOS/ShopMac/zh-Hans.lproj/Localizable.strings` only for Mac-only keys

**Interfaces:**
- Produces `ShopStrings` keys used by Tasks 5–6

- [ ] **Step 1: Add keys**

| Key | en | zh-Hans |
|-----|----|---------|
| `selection.select` | Select | 选择 |
| `selection.done` | Done | 完成 |
| `selection.count` | %d Selected | 已选 %d 项 |
| `selection.mark_all_complete` | Mark All Complete | 全部标为完成 |
| `selection.mark_all_incomplete` | Restore All | 全部恢复 |
| `selection.edit_tags` | Tags | 标签 |
| `selection.delete_confirm_title` | Delete Items? | 删除物品？ |
| `selection.delete_confirm_message` | Delete %d selected items? | 删除已选的 %d 项？ |
| `selection.tag_all` | All selected have this tag | 全部已选拥有此标签 |
| `selection.tag_some` | Some selected have this tag | 部分已选拥有此标签 |
| `selection.tag_none` | None selected have this tag | 已选均无此标签 |
| `undo.batch_items_changed` | Undo batch change | 撤销批量更改 |
| `undo.batch_items_deleted` | Undo batch delete | 撤销批量删除 |
| `undo.batch_tags_changed` | Undo tag change | 撤销标签更改 |

Wire via `ShopStrings` with `bundle: .module` like other ShopCore strings. Use `String(format: ShopStrings.selectionCountFormat, count)` or a helper:

```swift
public static func selectionCount(_ count: Int) -> String {
    String(format: NSLocalizedString("selection.count", bundle: .module, comment: ""), count)
}
```

- [ ] **Step 2: Build ShopCore tests to ensure strings compile**

```bash
cd "/Users/wangshaoyan/code/shop!/Shared" && swift test --filter ItemSelectionTests
```

---

### Task 5: iPhone multi-select UI

**Files:**
- Modify: `iOS/Shop/ContentView.swift`
- Modify: `iOS/Shop/Views/ItemListView.swift`
- Create: `iOS/Shop/Views/BatchActionBar.swift`

**Interfaces:**
- Consumes: Task 1–4 APIs
- Produces: working iPhone select mode + batch bar + tag sheet + delete confirm

- [ ] **Step 1: State in `ContentView`**

```swift
@State private var isSelecting = false
@State private var selectedItemIDs: Set<UUID> = []
@State private var showBatchTags = false
@State private var showBatchDeleteConfirm = false
```

- [ ] **Step 2: Toolbar Select / Done**

In trailing toolbar, before undo/settings when `!filteredItems.isEmpty`:

```swift
Button(isSelecting ? ShopStrings.selectionDone : ShopStrings.selectionSelect) {
    if isSelecting {
        isSelecting = false
        selectedItemIDs = []
    } else {
        isSelecting = true
    }
}
```

Hide FAB while `isSelecting`.

- [ ] **Step 3: Pass selection into `ItemListView`**

```swift
ItemListView(
    filteredItems: filteredItems,
    searchIsActive: !searchText.isEmpty,
    isSelecting: isSelecting,
    selectedItemIDs: $selectedItemIDs,
    onEnterSelection: { item in
        isSelecting = true
        selectedItemIDs = [item.id]
        ShopHaptics.itemRestored() // single light pulse; or add selectionChanged if desired
    },
    onEditItem: { item in editorMode = .edit(item) }
)
```

Prune selection when `filteredItems` changes:

```swift
.onChange(of: filteredItems.map(\.id)) { _, ids in
    selectedItemIDs = ItemSelection.prunedSelection(selectedItemIDs, visibleIDs: Set(ids))
    if isSelecting, selectedItemIDs.isEmpty, /* optional: keep mode until Done */ false {
        // Spec: empty selection exits multi-select after delete; keep mode while user is selecting zero after deselect — follow spec:
        // "选择集合变空时自动退出多选模式"
        isSelecting = false
    }
}
```

After successful batch delete, clear selection and set `isSelecting = false`.

- [ ] **Step 4: Update `ItemListView` rows**

When `isSelecting`:
- Leading control becomes selection circle (brand fill + checkmark when selected)
- Row tap toggles membership in `selectedItemIDs`
- Disable swipeActions
- Ignore `onEdit` / completion button
- `.onLongPressGesture` on row when `!isSelecting` calls `onEnterSelection(item)`

- [ ] **Step 5: `BatchActionBar`**

Bottom `safeAreaInset` when `isSelecting`:

```swift
BatchActionBar(
    selectedCount: selectedItemIDs.count,
    onComplete: { ... dataStore.setCompleted(Array(selectedItemIDs), completed: true, presentUndo:) ... },
    onRestore: { ... completed: false ... },
    onTags: { showBatchTags = true },
    onDelete: { showBatchDeleteConfirm = true }
)
```

Delete alert:

```swift
.alert(ShopStrings.selectionDeleteConfirmTitle, isPresented: $showBatchDeleteConfirm) {
    Button(ShopStrings.deleteItem, role: .destructive) {
        dataStore.deleteItems(Array(selectedItemIDs), presentUndo: undoCoordinator.present)
        selectedItemIDs = []
        isSelecting = false
    }
    Button(ShopStrings.dismiss, role: .cancel) {}
} message: {
    Text(ShopStrings.selectionDeleteConfirmMessage(selectedItemIDs.count))
}
```

Tag sheet: list all `dataStore.tags` with tri-state from `ItemSelection.membership`; tap applies add/remove via DataStore batch APIs; haptic once per apply.

- [ ] **Step 6: Build iOS**

```bash
cd "/Users/wangshaoyan/code/shop!" && xcodebuild -scheme Shop -destination 'generic/platform=iOS' -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 7: Manual checklist**
- Select button enters mode; Done exits
- Long-press enters with that item selected
- Row tap toggles; swipe/edit disabled
- Complete/Restore work on mixed sets as absolute actions
- Delete confirms with count and exits selection
- Tag tri-state add/remove works

---

### Task 6: Mac multi-select + Shift/Command + batch detail

**Files:**
- Modify: `macOS/ShopMac/ContentView.swift`

**Interfaces:**
- Consumes: Task 1–4 APIs
- Produces: Mac selection semantics + batch detail panel

- [ ] **Step 1: Replace single selection state**

```swift
@State private var selectedItemIDs: Set<UUID> = []
@State private var selectionAnchorID: UUID?
@State private var showBatchDeleteConfirm = false
```

Derived:

```swift
private var selectedItems: [ShoppingItem] {
    dataStore.items.filter { selectedItemIDs.contains($0.id) }
}
private var isMultiSelecting: Bool { selectedItemIDs.count > 1 }
```

Keep draft behavior: `beginDraft()` clears `selectedItemIDs` and `selectionAnchorID`.

- [ ] **Step 2: Selection handler**

```swift
private func handleItemClick(_ item: ShoppingItem, modifiers: EventModifiers) {
    let ordered = ItemSelection.visualOrderedIDs(
        from: ItemListSections.derive(from: filteredItems, groupOption: dataStore.groupOption)
    )
    let command = modifiers.contains(.command)
    let shift = modifiers.contains(.shift)

    if shift, let anchor = selectionAnchorID {
        let range = ItemSelection.range(from: anchor, to: item.id, in: ordered)
        if command {
            selectedItemIDs.formUnion(range)
        } else {
            selectedItemIDs = Set(range)
        }
    } else if command {
        if selectedItemIDs.contains(item.id) {
            selectedItemIDs.remove(item.id)
        } else {
            selectedItemIDs.insert(item.id)
        }
        selectionAnchorID = item.id
    } else {
        selectedItemIDs = [item.id]
        selectionAnchorID = item.id
    }
    isDrafting = false
    ShopHaptics.itemRestored() // single pulse for selection change is optional; prefer only on batch actions if noisy
}
```

Pass modifiers from `MacItemRow` via `NSEvent.modifierFlags` on click, or use a `Button`/`simultaneousGesture` that reads `NSApp.currentEvent?.modifierFlags`.

Recommended Mac row approach:

```swift
.onTapGesture {
    let mods = NSEvent.modifierFlags.intersection([.shift, .command])
    onSelect(item, EventModifiers(rawValue: UInt(mods.rawValue)))
}
```

Map AppKit flags carefully; simplest robust path:

```swift
private func currentClickModifiers() -> EventModifiers {
    var mods: EventModifiers = []
    let flags = NSEvent.modifierFlags
    if flags.contains(.shift) { mods.insert(.shift) }
    if flags.contains(.command) { mods.insert(.command) }
    return mods
}
```

- [ ] **Step 3: Highlight any selected ID**

```swift
isSelected: selectedItemIDs.contains(item.id)
```

Do not use `List(selection:)`.

- [ ] **Step 4: Detail column**

```swift
if isDrafting { MacDraftDetailView(...) }
else if selectedItemIDs.count > 1 { MacBatchDetailView(...) }
else if let id = selectedItemIDs.first, item(for: id) != nil { MacItemDetailView(itemID: id, ...) }
else { detailPlaceholder }
```

`MacBatchDetailView` shows:
- `ShopStrings.selectionCount(selectedItemIDs.count)`
- Buttons: Mark All Complete, Restore All, Tags (inline tri-state list), Delete

- [ ] **Step 5: Keyboard semantics**

- `onDeleteCommand`: if multi-select → confirm delete all selected; if single → existing delete; if drafting → discard
- Space/Return: only when `selectedItemIDs.count == 1`; ignore when multi-select

- [ ] **Step 6: Prune selection**

```swift
.onChange(of: dataStore.items) { _, items in
    let visible = Set(filteredItems.map(\.id))
    selectedItemIDs = ItemSelection.prunedSelection(selectedItemIDs, visibleIDs: visible)
    if let anchor = selectionAnchorID, !selectedItemIDs.contains(anchor) {
        selectionAnchorID = selectedItemIDs.first
    }
}
```

Also prune when filter/search/group changes.

- [ ] **Step 7: Build Mac**

```bash
cd "/Users/wangshaoyan/code/shop!" && xcodebuild -scheme ShopMac -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 8: Manual checklist**
- Click selects one + shows detail
- ⌘-click toggles membership
- Shift-click selects visual range across groups/archive
- Shift+⌘ adds range to existing selection
- Multi-select shows count + batch panel
- Space/Return ignored while multi-selected
- Delete confirms with count
- Draft start clears multi-select

---

### Task 7: Full verification

**Files:** none new

- [ ] **Step 1: Shared tests**

```bash
cd "/Users/wangshaoyan/code/shop!/Shared" && swift test --filter ItemSelectionTests --filter DataStoreBatchTests --filter UndoCoordinatorTests
```

Expected: PASS

- [ ] **Step 2: App builds**

```bash
cd "/Users/wangshaoyan/code/shop!"
xcodebuild -scheme Shop -destination 'generic/platform=iOS' -configuration Debug CODE_SIGNING_ALLOWED=NO build
xcodebuild -scheme ShopMac -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Expected: both `BUILD SUCCEEDED`

- [ ] **Step 3: Spec coverage smoke**
- Mixed complete/restore absolute semantics
- Tri-state tags
- Delete confirm with count
- Mac Shift/Command
- iPhone toolbar + long-press
- Empty selection exits iPhone select mode after delete / prune-to-empty

---

## Spec Coverage Self-Check

| Spec requirement | Task |
|------------------|------|
| `Set<UUID>` view-local selection | 5, 6 |
| Batch complete / restore / tags / delete | 2, 3 |
| Absolute complete/restore on mixed sets | 2, 3, 5, 6 |
| One mutation + one undo | 2, 3 |
| iPhone Select + long-press | 5 |
| iPhone disable swipe/edit in select mode | 5 |
| iPhone bottom bar + confirm delete | 5 |
| Mac click / ⌘ / Shift / Shift+⌘ | 1, 6 |
| Visual order across groups/archive | 1, 6 |
| Mac batch detail with count | 6 |
| Space/Return single-only | 6 |
| Tag tri-state | 1, 5, 6 |
| Prune invisible selection | 1, 5, 6 |
| Soft-delete sync semantics | 2 |
| Tests listed in spec | 1, 2, 3, 7 |
