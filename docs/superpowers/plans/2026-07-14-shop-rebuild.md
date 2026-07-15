# Shop! Three-Platform Rebuild Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore a clean three-platform build, make WebDAV and Watch synchronization loss-resistant, and deliver the approved calm native interface with editing, inline archive, tags, and undo.

**Architecture:** Keep SwiftData as local persistence, but move snapshot encoding and conflict merging into pure value-type services. A single sync coordinator drives both WebDAV and WatchConnectivity transports, while each platform owns native SwiftUI views backed by shared store operations and presentation tokens.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, XCTest, URLSession/WebDAV, WatchConnectivity, Security/Keychain, XcodeGen.

## Global Constraints

- Minimum versions remain iOS 18, macOS 15, and watchOS 11.
- Use only Apple SDKs; do not add third-party dependencies.
- Preserve the existing `shop_sync.json` location and decode the existing unversioned JSON shape.
- Conflict policy is last modified wins with deterministic device-ID tie-breaking.
- Completed items appear as an archive section below active items in the same scroll view.
- iOS 26+ uses native Liquid Glass; supported older systems use Material fallback.
- Every user-facing string must be localized in English and Simplified Chinese.
- Do not create git commits unless the user explicitly authorizes commits.

## File Map

### Shared core

- `Shared/Sources/ShopCore/Models/ShoppingItem.swift`: persisted item fields only.
- `Shared/Sources/ShopCore/Models/Tag.swift`: persisted tag fields only.
- `Shared/Sources/ShopCore/Storage/DataStore.swift`: compatibility facade and observable queries.
- `Shared/Sources/ShopCore/Storage/ShoppingStore.swift`: transactional CRUD and snapshot application.
- `Shared/Sources/ShopCore/Sync/SyncSnapshot.swift`: versioned, Codable transfer values.
- `Shared/Sources/ShopCore/Sync/SnapshotMerger.swift`: pure deterministic merge.
- `Shared/Sources/ShopCore/Sync/SyncCoordinator.swift`: debounce, serialization, status, retry orchestration.
- `Shared/Sources/ShopCore/Sync/WebDAVTransport.swift`: HTTP transport and ETag conditional writes.
- `Shared/Sources/ShopCore/Sync/WatchConnectivityTransport.swift`: immediate and eventual Watch delivery.
- `Shared/Sources/ShopCore/Security/KeychainStore.swift`: WebDAV password storage.
- `Shared/Sources/ShopCore/Presentation/ShopTheme.swift`: semantic colors, spacing, Tag palette, glass fallback.
- `Shared/Sources/ShopCore/Undo/UndoCoordinator.swift`: one-level reversible mutation.

### Platform applications

- `iOS/Shop/ShopApp.swift`: dependency graph and appearance.
- `iOS/Shop/ContentView.swift`: active and archived sections.
- `iOS/Shop/Views/ItemListView.swift`: row interactions and accessibility.
- `iOS/Shop/Views/ItemEditorView.swift`: create/edit form.
- `iOS/Shop/Views/UndoBanner.swift`: reversible-action UI.
- `iOS/Shop/Views/SettingsView.swift`: appearance and sync state.
- `macOS/ShopMac/ContentView.swift`: split view and detail editor.
- `macOS/ShopMac/Views/MacSettingsView.swift`: WebDAV and full Tag management.
- `watchOS/ShopWatch/ContentView.swift`: active/archive list.
- `watchOS/ShopWatch/Views/WatchAddItemView.swift`: quick add with existing Tag selection.

### Tests and project files

- `Shared/Tests/ShopCoreTests/SnapshotMergerTests.swift`
- `Shared/Tests/ShopCoreTests/ShoppingStoreTests.swift`
- `Shared/Tests/ShopCoreTests/WebDAVTransportTests.swift`
- `Shared/Tests/ShopCoreTests/SyncCoordinatorTests.swift`
- `Shared/Tests/ShopCoreTests/UndoCoordinatorTests.swift`
- `project.yml`, `Shared/Package.swift`, platform asset catalogs, localization resources, and `README.md`

---

### Task 1: Restore the Clean Build Baseline

**Files:**
- Modify: `Shared/Package.swift:18-30`
- Modify: `iOS/Shop/Views/LiquidGlassComponents.swift:1-247`
- Modify: all SwiftUI files that currently use `tag.color`
- Modify: `project.yml`
- Test: `Shared/Tests/ShopCoreTests/DataStoreTests.swift`

**Interfaces:**
- Consumes: Existing `Tag.colorHex`.
- Produces: `Color.init(shopHex:)` and `Tag.displayColor`, available on all three UI platforms.

- [ ] **Step 1: Make the package failure reproducible**

Run:

```bash
cd Shared && swift test
```

Expected: FAIL with `Invalid Resource 'Resources': File not found`.

- [ ] **Step 2: Remove the nonexistent package resource declaration**

Change the target declaration to:

```swift
.target(
    name: "ShopCore",
    path: "Sources/ShopCore"
)
```

- [ ] **Step 3: Add the missing module import and central color conversion**

Add `import ShopCore` to `LiquidGlassComponents.swift`. Create the following in `Shared/Sources/ShopCore/Presentation/Color+ShopHex.swift`:

```swift
import SwiftUI

public extension Color {
    init?(shopHex: String) {
        let value = shopHex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let rgb = UInt64(value, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            opacity: 1
        )
    }
}

public extension Tag {
    var displayColor: Color {
        Color(shopHex: colorHex) ?? .blue
    }
}
```

Replace every SwiftUI use of `tag.color` with `tag.displayColor`. Delete the duplicate private `Color(hex:)` implementation.

- [ ] **Step 4: Regenerate the Xcode project and compile each target**

Run:

```bash
xcodegen generate
xcodebuild -scheme Shop -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -scheme ShopMac -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -scheme ShopWatch -destination 'generic/platform=watchOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: the missing resource, missing import, and `PlatformColor` conversion errors are gone. Record subsequent compiler errors and fix only baseline configuration/type errors before continuing.

- [ ] **Step 5: Run package tests**

Run: `cd Shared && swift test`

Expected: existing tests PASS.

### Task 2: Add Versioned Records and Transactional Store Operations

**Files:**
- Modify: `Shared/Sources/ShopCore/Models/ShoppingItem.swift`
- Modify: `Shared/Sources/ShopCore/Models/Tag.swift`
- Create: `Shared/Sources/ShopCore/Storage/ShoppingStore.swift`
- Modify: `Shared/Sources/ShopCore/Storage/DataStore.swift`
- Test: `Shared/Tests/ShopCoreTests/ShoppingStoreTests.swift`

**Interfaces:**
- Produces: `ShoppingStore.addItem`, `updateItem`, `setCompleted`, `softDeleteItem`, `restoreItem`, `deleteTag`, and `apply(snapshot:)`.
- Produces: persisted `updatedAt`, `deletedAt`, and `lastEditorDeviceID`.

- [ ] **Step 1: Write failing mutation tests**

Create tests covering timestamp advancement, soft deletion, Tag unlinking, and active/archive queries:

```swift
@MainActor
final class ShoppingStoreTests: XCTestCase {
    func testCompletingItemAdvancesVersionAndMovesItToArchive() throws {
        let store = try ShoppingStore(inMemory: true, deviceID: "iphone")
        let item = try store.addItem(name: "Milk", tagIDs: [])
        let oldVersion = item.updatedAt

        try store.setCompleted(itemID: item.id, completed: true, now: oldVersion.addingTimeInterval(1))

        XCTAssertTrue(try XCTUnwrap(store.item(id: item.id)).isCompleted)
        XCTAssertEqual(store.activeItems.count, 0)
        XCTAssertEqual(store.archivedItems.map(\.id), [item.id])
        XCTAssertGreaterThan(try XCTUnwrap(store.item(id: item.id)).updatedAt, oldVersion)
    }

    func testDeletingTagUnlinksItemsAndCreatesTagTombstone() throws {
        let store = try ShoppingStore(inMemory: true, deviceID: "mac")
        let tag = try store.addTag(name: "Food", colorHex: "#2F7D63")
        let item = try store.addItem(name: "Milk", tagIDs: [tag.id])

        try store.deleteTag(id: tag.id, now: Date())

        XCTAssertNotNil(store.tag(id: tag.id)?.deletedAt)
        XCTAssertTrue(try XCTUnwrap(store.item(id: item.id)).tags.isEmpty)
    }
}
```

- [ ] **Step 2: Run the focused tests**

Run: `cd Shared && swift test --filter ShoppingStoreTests`

Expected: FAIL because `ShoppingStore` and version fields do not exist.

- [ ] **Step 3: Add version fields with defaults**

Add to both persisted models:

```swift
public var updatedAt: Date
public var deletedAt: Date?
public var lastEditorDeviceID: String
```

Initialize `updatedAt` from `createdAt`, `deletedAt` as `nil`, and `lastEditorDeviceID` from the store-provided stable device ID.

- [ ] **Step 4: Implement transactional operations**

`ShoppingStore` must own `ModelContainer` and execute each public mutation on `@MainActor`. Use one save per user action, throw typed `ShoppingStoreError.saveFailed`, and never use `try?`. Query active records with `deletedAt == nil && isCompleted == false`; archived records with `deletedAt == nil && isCompleted == true`.

- [ ] **Step 5: Keep DataStore as a temporary UI facade**

Change existing `DataStore` methods to delegate to `ShoppingStore`, publish `activeItems` and `archivedItems`, and map thrown errors to a published `lastError`. Remove filtered-list reordering; allow reordering only in the unfiltered active section.

- [ ] **Step 6: Run store and legacy tests**

Run: `cd Shared && swift test --filter ShoppingStoreTests && swift test --filter DataStoreTests`

Expected: PASS.

### Task 3: Implement Versioned Snapshots and Deterministic Merge

**Files:**
- Create: `Shared/Sources/ShopCore/Sync/SyncSnapshot.swift`
- Create: `Shared/Sources/ShopCore/Sync/SnapshotMerger.swift`
- Test: `Shared/Tests/ShopCoreTests/SnapshotMergerTests.swift`
- Modify: `Shared/Sources/ShopCore/Storage/ShoppingStore.swift`

**Interfaces:**
- Produces: `SyncSnapshot(version:generatedAt:items:tags:)`.
- Produces: `SnapshotMerger.merge(local:remote:) -> SyncSnapshot`.
- Consumes: Store records from Task 2.

- [ ] **Step 1: Write failing merge tests**

Cover local-newer, remote-newer, equal-date device tie-break, tombstone precedence, missing Tag IDs, and duplicate replay:

```swift
func testNewerTombstonePreventsDeletedItemFromReviving() {
    let id = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    let t0 = Date(timeIntervalSince1970: 1_000)
    let t1 = Date(timeIntervalSince1970: 2_000)
    let oldLive = ItemSnapshot(
        id: id, name: "Milk", isCompleted: false,
        createdAt: t0, completedAt: nil, updatedAt: t0,
        deletedAt: nil, sortOrder: 0, tagIDs: [],
        lastEditorDeviceID: "iphone"
    )
    let newDelete = ItemSnapshot(
        id: id, name: "Milk", isCompleted: false,
        createdAt: t0, completedAt: nil, updatedAt: t1,
        deletedAt: t1, sortOrder: 0, tagIDs: [],
        lastEditorDeviceID: "mac"
    )

    let result = SnapshotMerger().merge(
        local: SyncSnapshot(version: 2, generatedAt: t0, items: [oldLive], tags: []),
        remote: SyncSnapshot(version: 2, generatedAt: t1, items: [newDelete], tags: [])
    )

    XCTAssertEqual(result.items.first?.deletedAt, t1)
}
```

- [ ] **Step 2: Run merge tests**

Run: `cd Shared && swift test --filter SnapshotMergerTests`

Expected: FAIL because snapshot types do not exist.

- [ ] **Step 3: Define stable Codable DTOs**

Use plain structs containing UUIDs and Tag IDs. Include:

```swift
public struct SyncSnapshot: Codable, Equatable, Sendable {
    public static let currentVersion = 2
    public let version: Int
    public let generatedAt: Date
    public var items: [ItemSnapshot]
    public var tags: [TagSnapshot]
}
```

Custom decoding must accept the current unversioned `{items,tags}` payload and assign `version = 1`, `updatedAt = createdAt`, `deletedAt = nil`, and `lastEditorDeviceID = "legacy"`.

- [ ] **Step 4: Implement pure merge**

For each ID, compare `(updatedAt, lastEditorDeviceID)` lexicographically. Merge Tags first. Filter each winning item’s `tagIDs` against nondeleted winning Tags. Sort output by UUID string to keep JSON deterministic.

- [ ] **Step 5: Add store snapshot export/application**

Add:

```swift
public func makeSnapshot(now: Date = Date()) throws -> SyncSnapshot
public func apply(snapshot: SyncSnapshot) throws
```

Application must upsert existing SwiftData objects instead of inserting duplicate model instances and must rebuild relationships using the store’s canonical Tag objects.

- [ ] **Step 6: Run all shared tests**

Run: `cd Shared && swift test`

Expected: PASS.

### Task 4: Implement WebDAV ETag Transport and Keychain Credentials

**Files:**
- Replace: `Shared/Sources/ShopCore/Sync/WebDAVSyncService.swift`
- Create: `Shared/Sources/ShopCore/Sync/WebDAVTransport.swift`
- Create: `Shared/Sources/ShopCore/Security/KeychainStore.swift`
- Test: `Shared/Tests/ShopCoreTests/WebDAVTransportTests.swift`

**Interfaces:**
- Produces: `WebDAVTransport.fetch() -> RemoteSnapshot?`.
- Produces: `WebDAVTransport.put(_:precondition:) -> String?`.
- Produces: `KeychainStore.setPassword`, `password`, and `deletePassword`.

- [ ] **Step 1: Write URLProtocol-backed failing tests**

Test GET 200 with ETag, GET 404, PUT creation with `If-None-Match: *`, update with `If-Match`, 401 mapping, 412 mapping, timeout, and malformed JSON.

```swift
func testConditionalUpdateSendsETag() async throws {
    StubURLProtocol.handler = { request in
        XCTAssertEqual(request.value(forHTTPHeaderField: "If-Match"), "\"v3\"")
        return (.http(status: 204, url: request.url!), Data())
    }
    let snapshot = SyncSnapshot(
        version: SyncSnapshot.currentVersion,
        generatedAt: Date(timeIntervalSince1970: 1_000),
        items: [],
        tags: []
    )
    _ = try await transport.put(snapshot, precondition: .etag("\"v3\""))
}
```

- [ ] **Step 2: Run transport tests**

Run: `cd Shared && swift test --filter WebDAVTransportTests`

Expected: FAIL because the transport does not exist.

- [ ] **Step 3: Implement typed transport errors**

Define `WebDAVError` cases for invalidURL, insecureURL, unauthorized, notFound, preconditionFailed, invalidResponse, decoding, and network. Require HTTPS unless an explicit `allowsInsecureHTTP` testing/development flag is enabled.

- [ ] **Step 4: Implement conditional GET/PUT**

Use an injected `URLSession`, Basic Auth header, JSON content type, ETag response parsing, and no global ATS exception. Preserve the server path and append `shop_sync.json`.

- [ ] **Step 5: Implement Keychain storage**

Use Security framework generic-password items keyed by bundle-independent service `com.shop.webdav` and account `username@serverURL`. Treat `errSecItemNotFound` as no password; throw all other OSStatus values.

- [ ] **Step 6: Replace plain password AppStorage**

Keep server URL and username in AppStorage. On save, move the entered password into Keychain and remove `webdav_password` from UserDefaults on both iOS and macOS.

- [ ] **Step 7: Run transport and full shared tests**

Run: `cd Shared && swift test`

Expected: PASS.

### Task 5: Build the Serialized Auto-Sync Coordinator

**Files:**
- Create: `Shared/Sources/ShopCore/Sync/SyncCoordinator.swift`
- Test: `Shared/Tests/ShopCoreTests/SyncCoordinatorTests.swift`
- Modify: `iOS/Shop/ShopApp.swift`
- Modify: `macOS/ShopMac/ShopMacApp.swift`

**Interfaces:**
- Consumes: `ShoppingStore`, `SnapshotMerger`, and WebDAV transport.
- Produces: `scheduleSync()`, `syncNow() async`, and published `SyncStatus`.

- [ ] **Step 1: Write failing coordinator tests**

Use a fake transport to verify debounce coalescing, single-flight execution, GET/merge/apply/conditional-PUT order, 412 refetch and bounded retry, and local edits remaining available after network failure.

- [ ] **Step 2: Run coordinator tests**

Run: `cd Shared && swift test --filter SyncCoordinatorTests`

Expected: FAIL because `SyncCoordinator` does not exist.

- [ ] **Step 3: Implement status and scheduling**

Define:

```swift
public enum SyncStatus: Equatable, Sendable {
    case idle(lastSuccess: Date?)
    case syncing
    case failed(message: String, canRetry: Bool)
}
```

Make the coordinator `@MainActor`. Debounce local changes by two seconds. Serialize operations through one stored `Task`; if a change arrives while syncing, set `needsAnotherPass` and run once more after completion.

- [ ] **Step 4: Implement ETag conflict retry**

Perform GET → merge → local apply → conditional PUT. On 412, refetch and retry up to three total attempts. Do not discard local records when all attempts fail.

- [ ] **Step 5: Inject one coordinator instance per app**

iOS and macOS app roots must configure the same store, transport, and coordinator instance used by settings UI. Delete the macOS code that creates an unbound temporary WebDAV service.

- [ ] **Step 6: Run tests and no-sign builds**

Run shared tests and iOS/macOS builds from Task 1.

Expected: PASS.

### Task 6: Make WatchConnectivity Immediate and Eventually Consistent

**Files:**
- Replace: `Shared/Sources/ShopCore/Sync/WiFiSyncService.swift`
- Create: `Shared/Sources/ShopCore/Sync/WatchConnectivityTransport.swift`
- Modify: `iOS/Shop/ShopApp.swift`
- Modify: `watchOS/ShopWatch/ShopWatchApp.swift`
- Test: `Shared/Tests/ShopCoreTests/WatchSnapshotHandlerTests.swift`

**Interfaces:**
- Produces: `sendLatestSnapshot()`, `requestLatestSnapshot()`, and `handleReceivedSnapshot(_:)`.
- Consumes: Task 3 merger and store.

- [ ] **Step 1: Test the platform-independent receive handler**

Verify duplicate messages are idempotent, Watch-newer edits win, iPhone-newer edits remain, and tombstones propagate.

- [ ] **Step 2: Replace the misleading WiFi-only abstraction**

Rename UI-facing concepts to device sync or Watch sync. Implement `WCSessionDelegate` callbacks as `nonisolated` where required by Swift 6, then hop to `MainActor` before touching store or published state.

- [ ] **Step 3: Implement two delivery paths**

When reachable, use `sendMessage` with a reply. Always update application context with the latest snapshot. If encoded data exceeds the application-context budget, write to a temporary JSON file and use `transferFile`.

- [ ] **Step 4: Add automatic triggers**

Send after local mutation debounce, session activation, reachability restoration, and app foreground. The Watch requests a snapshot after activation and sends its local changes after add/complete/restore.

- [ ] **Step 5: Verify Watch embedding and build**

Regenerate the project. Confirm the iOS archive embeds the Watch app and build both `Shop` and `ShopWatch` without signing.

### Task 7: Add Reversible Mutations and Inline Archive Behavior

**Files:**
- Create: `Shared/Sources/ShopCore/Undo/UndoCoordinator.swift`
- Test: `Shared/Tests/ShopCoreTests/UndoCoordinatorTests.swift`
- Modify: `Shared/Sources/ShopCore/Storage/ShoppingStore.swift`

**Interfaces:**
- Produces: `UndoCoordinator.present(action:)`, `undo()`, `dismiss()`.
- Consumes: Store operations from Task 2.

- [ ] **Step 1: Write failing undo tests**

Test complete, restore, item delete, and Tag delete. Verify undo creates a later `updatedAt` and schedules synchronization.

- [ ] **Step 2: Implement one-level undo actions**

Use:

```swift
public struct UndoAction: Identifiable {
    public let id: UUID
    public let message: String
    public let perform: @MainActor () throws -> Void
}
```

Present one action for five seconds. Replacing an existing action dismisses the older one. Undo performs a new store mutation; it never restores stale model object references.

- [ ] **Step 3: Run undo and merge tests**

Run: `cd Shared && swift test --filter UndoCoordinatorTests && swift test --filter SnapshotMergerTests`

Expected: PASS.

### Task 8: Rebuild the iPhone/iPad Experience

**Files:**
- Modify: `iOS/Shop/ContentView.swift`
- Replace: `iOS/Shop/Views/ItemListView.swift`
- Replace: `iOS/Shop/Views/AddItemView.swift`
- Create: `iOS/Shop/Views/ItemEditorView.swift`
- Create: `iOS/Shop/Views/UndoBanner.swift`
- Refactor: `iOS/Shop/Views/LiquidGlassComponents.swift`
- Modify: `iOS/Shop/Views/FilterView.swift`
- Modify: `iOS/Shop/Views/TagManagementView.swift`

**Interfaces:**
- Consumes: `activeItems`, `archivedItems`, store mutations, undo coordinator, and theme tokens.
- Produces: Approved tap, circle, bidirectional swipe, edit, Tag, and undo behavior.

- [ ] **Step 1: Add UI-facing unit tests for section derivation**

Test that active rows precede an archive header and archived rows, and filtering never changes the underlying reorder indices.

- [ ] **Step 2: Implement one scroll surface**

Use a single `List` with an active `Section` followed by an archive `Section`. Do not navigate to a separate archive screen.

- [ ] **Step 3: Implement row actions**

The circle button and both leading/trailing completion actions call `setCompleted`. Tapping the remaining row opens `ItemEditorView`. Keep destructive delete as an explicitly labeled secondary swipe action. Every reversible action presents `UndoBanner`.

- [ ] **Step 4: Implement create/edit parity**

Use one editor for new and existing items. Require a nonblank name, allow zero or more Tag IDs, preserve unsaved changes on accidental interactive dismissal, and call the matching store operation once.

- [ ] **Step 5: Apply calm native styling**

Use semantic natural-green tint, system typography, restrained Material surfaces, 4/8pt spacing, and at most one primary action per screen. Gate native glass modifiers with `if #available(iOS 26, *)`; use Material fallback otherwise.

- [ ] **Step 6: Fix filtering and accessibility**

Replace the six-option segmented picker with a menu or grouped list. Add labels/hints/selected state, 44pt targets, Dynamic Type-safe wrapping, and reduced-motion alternatives.

- [ ] **Step 7: Build and manually exercise**

Build iOS without signing. Exercise add, edit, no-Tag item, multi-Tag item, circle completion, both swipes, inline archive, restore, delete, undo, search, and filtering.

### Task 9: Rebuild macOS as a Native Split-View App

**Files:**
- Replace: `macOS/ShopMac/ContentView.swift`
- Replace: `macOS/ShopMac/Views/MacSettingsView.swift`
- Modify: `macOS/ShopMac/ShopMacApp.swift`

**Interfaces:**
- Consumes: shared store, sync coordinator, Keychain, theme, and Tag operations.
- Produces: sidebar filters, list selection, detail editing, full Tag management, and keyboard shortcuts.

- [ ] **Step 1: Bind sidebar state directly to shared filters**

Remove duplicated local/shared filter state. Show selected Tag state visually and expose sync status at the bottom.

- [ ] **Step 2: Implement list and detail selection**

Toggling the check control completes/restores; selecting the row edits name and Tags in the detail column. Preserve selection after edits and clear it after deletion.

- [ ] **Step 3: Fix settings dependency injection**

Use the app’s existing coordinator and store. Save credentials through Keychain. Provide add, rename, recolor, delete, and undo for Tags.

- [ ] **Step 4: Add real shortcuts**

Implement Command-N for add, Command-F for search, Delete for selected item with undo, and Command-R for sync. Make empty-state copy match the registered shortcuts.

- [ ] **Step 5: Build and manually exercise**

Build `ShopMac` without signing and test resizable windows, keyboard-only operation, light/dark appearance, Tag management, sync status, and item editing.

### Task 10: Complete the Watch Companion

**Files:**
- Replace: `watchOS/ShopWatch/ContentView.swift`
- Replace: `watchOS/ShopWatch/Views/WatchAddItemView.swift`

**Interfaces:**
- Consumes: active/archive items, existing Tags, store operations, and Watch sync transport.
- Produces: fast view/complete/restore/add flow with Tag selection.

- [ ] **Step 1: Show active and archived sections**

Keep active items first and archived items after a clear header. Use semantic fonts and permit two-line item names.

- [ ] **Step 2: Add completion and restore actions**

Make the primary check control explicit and accessible. Trigger haptics only for confirmed completion, restore, and successful add.

- [ ] **Step 3: Add existing Tag selection**

Present a compact multi-select list beneath the name field. Do not expose Tag creation or management.

- [ ] **Step 4: Trigger device sync**

After add, complete, or restore, schedule snapshot delivery. Display a small nonblocking failure status without preventing local use.

- [ ] **Step 5: Build and verify Watch layouts**

Build `ShopWatch` without signing and inspect small and large Watch simulator sizes with large accessibility text.

### Task 11: Finish Appearance, Icons, Localization, and Documentation

**Files:**
- Modify: `iOS/Shop/ShopApp.swift`
- Modify: all platform `Assets.xcassets`
- Modify: `iOS/Shop/Info.plist`
- Modify: `Shared/Sources/ShopCore/Localization/Strings.swift`
- Modify: platform `Localizable.strings`
- Modify: `README.md`

**Interfaces:**
- Produces: functional system/light/dark appearance and valid platform icon sets.

- [ ] **Step 1: Apply appearance at each root**

Map stored values to `ColorScheme?` and apply `.preferredColorScheme`. Keep system mode as `nil`.

- [ ] **Step 2: Correct app icon assets**

Provide valid source artwork and generate all required iOS, macOS, and watchOS slots. Use iOS asset-catalog light, dark, and tinted appearances. Remove the nonexistent `AppIcon-Dark` alternate declaration unless an actual user-selectable alternate icon is delivered.

- [ ] **Step 3: Complete localization**

Add keys for archive, restore, edit item, undo, sync states, conflict retry, insecure URL, custom date range, appearance options, and keyboard hints. Remove every hardcoded user-facing English string from Swift files.

- [ ] **Step 4: Update README to match reality**

Describe WatchConnectivity accurately, remove the CloudKit claim, document Keychain-backed WebDAV, automatic/manual sync, minimum versions, build commands, and actual schemes.

- [ ] **Step 5: Validate assets and localization**

Build all schemes and inspect build logs for missing asset names or localization warnings.

### Task 12: Final Verification and Regression Gate

**Files:**
- Modify only files required by failures discovered below.

**Interfaces:**
- Consumes: all preceding tasks.
- Produces: verified release candidate with documented residual hardware-only checks.

- [ ] **Step 1: Run the complete shared test suite**

Run: `cd Shared && swift test`

Expected: all tests PASS with zero warnings from missing resources.

- [ ] **Step 2: Run three no-sign builds**

Run:

```bash
xcodebuild -scheme Shop -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -scheme ShopMac -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -scheme ShopWatch -destination 'generic/platform=watchOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **` for all three.

- [ ] **Step 3: Run static project checks**

Run:

```bash
git diff --check
rg 'try\\?' Shared iOS macOS watchOS
rg 'webdav_password' Shared iOS macOS watchOS
rg 'Text\\("[A-Za-z]' iOS macOS watchOS
```

Expected: no whitespace errors; no silent persistence/network errors; no plain password storage; every remaining literal is intentionally non-user-facing or localized.

- [ ] **Step 4: Perform simulator/manual accessibility checks**

Verify light/dark/system appearance, largest Dynamic Type, VoiceOver labels/order, Reduce Motion, 44pt targets, iPhone portrait/landscape, iPad split view, resizable Mac window, and small/large Watch.

- [ ] **Step 5: Perform synchronization scenarios**

Using a disposable WebDAV account, verify first upload, normal merge, offline concurrent edit, concurrent delete/edit, 412 retry, bad credentials, timeout and recovery. On paired hardware, verify iPhone/Watch add, complete, restore, offline delivery, reconnect, and duplicate-message idempotency.

- [ ] **Step 6: Record hardware-only limitations**

If paired Watch hardware or a disposable WebDAV server is unavailable, list those scenarios explicitly as unverified. Do not claim them passing based only on unit tests.
