# Widget Redesign + Background Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign iPhone/Mac widgets (layout, tags, recently completed restore, deep-link add, per-instance tag filter) and add best-effort scheduled background sync with coalesced post-widget refresh.

**Architecture:** ShopCore owns snapshot, filter helpers, pending queues, and schedule interval math. WidgetKit uses `AppIntentConfiguration` for per-instance tag filter. Host apps register background refresh (iOS `BGAppRefreshTask`, macOS `NSBackgroundActivityScheduler`), consume widget queues, sync WebDAV, and republish snapshots. Widget intents optimistically mutate App Group state and set a single `needsSync` flag.

**Tech Stack:** SwiftUI, WidgetKit, AppIntents, BackgroundTasks (iOS), NSBackgroundActivityScheduler (macOS), App Group, ShopCore, XcodeGen.

## Global Constraints

- Min versions: iOS 18 / macOS 15 / watchOS 11 (Watch unchanged; no widgets).
- Theme: `ShopTheme.brandColor` = `#C53A32`.
- No in-widget keyboard text input; add opens `shop://add`.
- No widget refresh button.
- Background sync is best-effort; do not claim exact timing.
- Spec: `docs/superpowers/specs/2026-07-16-widget-redesign-background-sync-design.md`.
- Commits: only when the user asks (unless they later approve per-task commits).

---

## File Structure

| Path | Responsibility |
|------|----------------|
| `Shared/.../Widgets/WidgetSnapshotStore.swift` | Snapshot, queues, `needsSync`, publish/load |
| `Shared/.../Widgets/WidgetItemFilter.swift` | OR/AND / all-tags filtering |
| `Shared/.../Widgets/WidgetTagDisplay.swift` | Named tags + color-dot truncation rules |
| `Shared/.../Widgets/BackgroundSyncSchedule.swift` | Day 1h / night 3h interval helper |
| `Shared/.../Storage/DataStore.swift` | Publish enriched snapshot; apply complete+restore queues |
| `Shared/.../Localization/*` | New widget/filter/background strings |
| `Widgets/Shared/ShopWidget.swift` | AppIntentConfiguration UI, intents, entities |
| `iOS/Shop/ShopApp.swift` + `Info.plist` | URL scheme, BGTask register/schedule, open add |
| `macOS/ShopMac/ShopMacApp.swift` + `Info.plist` | URL scheme, background activity, open add |
| `Shared/Tests/ShopCoreTests/WidgetSnapshotStoreTests.swift` | Snapshot/queue/filter/schedule tests |
| `project.yml` / entitlements / Info.plists | BGTask identifiers, URL types, background modes |

---

### Task 1: Extend snapshot model + queues (TDD)

**Files:**
- Modify: `Shared/Sources/ShopCore/Widgets/WidgetSnapshotStore.swift`
- Create: `Shared/Tests/ShopCoreTests/WidgetSnapshotStoreTests.swift`

**Interfaces:**
- Produces:
  - `TagInfo(id:name:colorHex:)`
  - `Entry(id:name:sortOrder:tags:completedAt:)`
  - `Snapshot(items:recentlyCompleted:availableTags:updatedAt:)`
  - `publish(activeItems:recentlyCompleted:availableTags:)`
  - `markCompleteInSnapshot(itemID:)`, `restoreInSnapshot(itemID:)`
  - `loadPendingCompletions()`, `loadPendingRestores()`, clear helpers
  - `markNeedsSync()`, `clearNeedsSync()`, `needsSync` / `loadNeedsSync()`

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import ShopCore

final class WidgetSnapshotStoreTests: XCTestCase {
    func testDecodesLegacySnapshotWithoutNewFields() throws {
        let legacy = """
        {"items":[{"id":"\(UUID().uuidString)","name":"Milk","sortOrder":0}],"updatedAt":0}
        """.data(using: .utf8)!
        let snapshot = try JSONDecoder().decode(WidgetSnapshotStore.Snapshot.self, from: legacy)
        XCTAssertEqual(snapshot.items.count, 1)
        XCTAssertTrue(snapshot.recentlyCompleted.isEmpty)
        XCTAssertTrue(snapshot.availableTags.isEmpty)
    }

    func testPublishOrdersRecentlyCompletedAndCapsAt20() {
        // Build 25 completed entries with ascending completedAt;
        // publish; load; assert count == 20 and first is newest.
    }

    func testMarkCompleteMovesItemToRecentlyCompletedAndQueuesID() {
        // publish one active item; markComplete; assert active empty,
        // recentlyCompleted has item, pending completions contains id, needsSync true.
    }

    func testRestoreMovesItemBackAndQueuesRestore() {
        // start with recentlyCompleted; restore; assert active has item,
        // pending restores contains id, needsSync true.
    }

    func testRepeatedMarkNeedsSyncStaysSingleFlag() {
        WidgetSnapshotStore.markNeedsSync()
        WidgetSnapshotStore.markNeedsSync()
        XCTAssertTrue(WidgetSnapshotStore.loadNeedsSync())
    }
}
```

- [ ] **Step 2: Run tests — expect FAIL** (missing types/APIs)

```bash
cd "/Users/wangshaoyan/code/shop!/Shared" && swift test --filter WidgetSnapshotStoreTests
```

- [ ] **Step 3: Implement snapshot store**

Update `TagInfo` to include `id: UUID` (decode-compatible: if missing, synthesize unstable UUID only for display — prefer requiring id on new publishes).

```swift
public struct TagInfo: Codable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let colorHex: String
}

public struct Entry: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let sortOrder: Int
    public let tags: [TagInfo]
    public let completedAt: Date?
    // decode tags/completedAt with defaults
}

public struct Snapshot: Codable, Sendable {
    public var items: [Entry]
    public var recentlyCompleted: [Entry]
    public var availableTags: [TagInfo]
    public var updatedAt: Date
    // decode missing arrays as []
}

public static let recentlyCompletedLimit = 20

public static func publish(
    activeItems: [(id: UUID, name: String, sortOrder: Int, tags: [(id: UUID, name: String, colorHex: String)])],
    recentlyCompleted: [(id: UUID, name: String, sortOrder: Int, tags: [(id: UUID, name: String, colorHex: String)], completedAt: Date)],
    availableTags: [(id: UUID, name: String, colorHex: String)]
) { /* map + sort + cap recentlyCompleted */ }

@discardableResult
public static func markCompleteInSnapshot(itemID: UUID) -> Bool {
    // remove from items → prepend to recentlyCompleted with completedAt = Date()
    // enqueue pending completion; markNeedsSync(); write
}

@discardableResult
public static func restoreInSnapshot(itemID: UUID) -> Bool {
    // remove from recentlyCompleted → insert into items by sortOrder
    // enqueue pending restore; markNeedsSync(); write
}
```

Add pending restores file/defaults key parallel to completions. Add `needsSync` bool in shared defaults (and optional file).

Keep dual-write (file + `UserDefaults(suiteName:)`).

- [ ] **Step 4: Re-run tests — expect PASS**

- [ ] **Step 5: Commit only if user asked**

---

### Task 2: Filter + tag display helpers (TDD)

**Files:**
- Create: `Shared/Sources/ShopCore/Widgets/WidgetItemFilter.swift`
- Create: `Shared/Sources/ShopCore/Widgets/WidgetTagDisplay.swift`
- Modify: `Shared/Tests/ShopCoreTests/WidgetSnapshotStoreTests.swift` (or new `WidgetFilterTests.swift`)

**Interfaces:**
- Produces:
  - `enum WidgetTagMatchMode: String, Codable { case any, all }`
  - `WidgetItemFilter.filtered(items:selectedTagIDs:matchMode:) -> [Entry]`
  - `WidgetTagDisplay.presentation(tags:namedLimit:) -> (named: [TagInfo], colorOnly: [TagInfo])`

- [ ] **Step 1: Failing tests**

```swift
func testFilterAllTagsOrEmptySelectionReturnsAll() { … }
func testFilterORMatchesAnySelectedTag() { … }
func testFilterANDRequiresEverySelectedTag() { … }
func testFilterIgnoresMissingTagIDsAndFallsBackWhenAllInvalid() { … }
func testSmallNamedLimitShowsOneNameRestColorOnly() {
    let result = WidgetTagDisplay.presentation(tags: fourTags, namedLimit: 1)
    XCTAssertEqual(result.named.count, 1)
    XCTAssertEqual(result.colorOnly.count, 3)
}
func testMediumNamedLimitShowsThreeNames() { … }
```

Rules from spec:
- Empty `selectedTagIDs` OR sentinel all-tags → return all items.
- If selected IDs exist but none match any item tags after dropping unknown IDs → treat as all-tags (avoid permanent empty).
- OR: intersection non-empty; AND: selected ⊆ item.tags.

- [ ] **Step 2: Implement helpers**

```swift
public enum WidgetTagMatchMode: String, Codable, Sendable, CaseIterable {
    case any
    case all
}

public enum WidgetItemFilter {
    public static let allTagsSentinel = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    public static func filtered(
        items: [WidgetSnapshotStore.Entry],
        selectedTagIDs: Set<UUID>,
        matchMode: WidgetTagMatchMode
    ) -> [WidgetSnapshotStore.Entry] {
        let effective = selectedTagIDs.subtracting([allTagsSentinel])
        guard !selectedTagIDs.isEmpty,
              !selectedTagIDs.contains(allTagsSentinel),
              !effective.isEmpty else { return items }
        // if effective has no overlap with any known tag ids across items → return items
        return items.filter { item in
            let ids = Set(item.tags.map(\.id))
            switch matchMode {
            case .any: return !ids.isDisjoint(with: effective)
            case .all: return effective.isSubset(of: ids)
            }
        }
    }
}

public enum WidgetTagDisplay {
    public static func presentation(
        tags: [WidgetSnapshotStore.TagInfo],
        namedLimit: Int
    ) -> (named: [WidgetSnapshotStore.TagInfo], colorOnly: [WidgetSnapshotStore.TagInfo]) {
        let named = Array(tags.prefix(namedLimit))
        let colorOnly = Array(tags.dropFirst(namedLimit))
        return (named, colorOnly)
    }
}
```

- [ ] **Step 3: Tests PASS**

---

### Task 3: Background schedule helper (TDD)

**Files:**
- Create: `Shared/Sources/ShopCore/Widgets/BackgroundSyncSchedule.swift`
- Create: `Shared/Tests/ShopCoreTests/BackgroundSyncScheduleTests.swift`

**Interfaces:**
- Produces: `BackgroundSyncSchedule.nextEarliestBeginDate(after:calendar:) -> Date`
- Day window 07:00–22:00 → +1 hour; else → +3 hours (local timezone).

- [ ] **Step 1: Failing tests**

```swift
func testDaytimeRequestsOneHour() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(secondsFromGMT: 0)!
    let noon = cal.date(from: DateComponents(year: 2026, month: 7, day: 16, hour: 12))!
    let next = BackgroundSyncSchedule.nextEarliestBeginDate(after: noon, calendar: cal)
    XCTAssertEqual(cal.dateComponents([.hour], from: noon, to: next).hour, 1)
}

func testNightRequestsThreeHours() {
    // 23:00 → +3h
}

func testBoundary0700IsDay() { /* 07:00 → +1h */ }
func testBoundary2200IsNight() { /* 22:00 → +3h */ }
```

- [ ] **Step 2: Implement**

```swift
public enum BackgroundSyncSchedule {
    public static func nextEarliestBeginDate(
        after date: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        let hour = calendar.component(.hour, from: date)
        let interval: TimeInterval = (hour >= 7 && hour < 22) ? 3600 : 3 * 3600
        return date.addingTimeInterval(interval)
    }
}
```

- [ ] **Step 3: Tests PASS**

---

### Task 4: DataStore publish + apply complete/restore queues

**Files:**
- Modify: `Shared/Sources/ShopCore/Storage/DataStore.swift` (`publishWidgetSnapshot`, `applyPendingWidgetCompletions` → rename/generalize)
- Modify: `Shared/Tests/ShopCoreTests/DataStoreTests.swift` (add cases)

**Interfaces:**
- Consumes: Task 1 publish signature
- Produces:
  - `publishWidgetSnapshot()` enriched
  - `applyPendingWidgetMutations()` applies completions then restores, then publish

- [ ] **Step 1: Failing DataStore tests**

```swift
func testPublishWidgetSnapshotIncludesRecentlyCompletedAndTagIDs() async throws {
    // add item+tag, complete it, publish; load snapshot; assert recentlyCompleted + availableTags ids
}

func testApplyPendingRestoreUncompletesItem() throws {
    // complete item, manually enqueue restore id, applyPendingWidgetMutations; assert active
}
```

- [ ] **Step 2: Implement**

```swift
public func publishWidgetSnapshot() {
    let completed = archivedItems
        .compactMap { item -> (…)? in
            guard let completedAt = item.completedAt else { return nil }
            return (id: item.id, name: item.name, sortOrder: item.sortOrder,
                    tags: mappedTags(item.tags), completedAt: completedAt)
        }
        .sorted { $0.completedAt > $1.completedAt }

    WidgetSnapshotStore.publish(
        activeItems: activeItems.map { … include tag ids … },
        recentlyCompleted: completed,
        availableTags: tags.map { (id: $0.id, name: $0.name, colorHex: $0.colorHex) }
    )
}

public func applyPendingWidgetMutations() {
    for id in WidgetSnapshotStore.loadPendingCompletions() {
        try? shoppingStore.setCompleted(itemID: id, completed: true)
    }
    WidgetSnapshotStore.clearPendingCompletions()

    for id in WidgetSnapshotStore.loadPendingRestores() {
        try? shoppingStore.setCompleted(itemID: id, completed: false)
    }
    WidgetSnapshotStore.clearPendingRestores()

    localMutationObservers.values.forEach { $0() }
    fetchData()
    publishWidgetSnapshot()
}
```

Keep `applyPendingWidgetCompletions()` as a deprecated wrapper calling `applyPendingWidgetMutations()` OR replace all call sites (ShopApp / ShopMacApp).

- [ ] **Step 3: Update call sites in iOS/macOS apps to `applyPendingWidgetMutations()`**

- [ ] **Step 4: Tests PASS**

---

### Task 5: Localization strings

**Files:**
- Modify: `Shared/Sources/ShopCore/Localization/Strings.swift`
- Modify: `Shared/Sources/ShopCore/Resources/en.lproj/Localizable.strings`
- Modify: `Shared/Sources/ShopCore/Resources/zh-Hans.lproj/Localizable.strings`

**Interfaces:**
- Produces ShopStrings keys used by widget + intents

- [ ] **Step 1: Add keys**

| Key | en | zh-Hans |
|-----|----|---------|
| `widget.recently_completed` | Recently Completed | 最近完成 |
| `widget.add_item` | Add Item | 添加物品 |
| `widget.restore_item` | Restore to Pending | 恢复为待买 |
| `widget.filter_all_tags` | All Tags | 全部标签 |
| `widget.match_any` | Match Any | 任一匹配 |
| `widget.match_all` | Match All | 全部匹配 |
| `widget.filter_empty` | No items for this filter | 该筛选下暂无物品 |

Wire `ShopStrings` accessors with `bundle: .module`.

- [ ] **Step 2: Build ShopCore tests compile**

---

### Task 6: Widget configuration entities + AppIntentConfiguration

**Files:**
- Modify: `Widgets/Shared/ShopWidget.swift` (large rewrite of provider/config; UI can stay stub until Task 7)

**Interfaces:**
- Produces:
  - `ShopTagEntity: AppEntity` with `id: UUID`, `name`
  - `ShopTagEntityQuery: EntityQuery` / `EntityStringQuery` reading `availableTags` from snapshot; include All Tags sentinel; only tags present on at least one **active** item (per spec), plus always include All Tags
  - `ShopWidgetConfigurationIntent: WidgetConfigurationIntent` with `@Parameter tags: [ShopTagEntity]?`, `@Parameter matchMode: MatchModeAppEnum`
  - `ShopWidgetProvider: AppIntentTimelineProvider`

- [ ] **Step 1: Define configuration**

```swift
enum WidgetMatchModeAppEnum: String, AppEnum {
    case any, all
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Match Mode")
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .any: "任一匹配", // use LocalizedStringResource from ShopStrings where possible
        .all: "全部匹配"
    ]
}

struct ShopTagEntity: AppEntity {
    var id: UUID
    var name: String
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Tag")
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    static var defaultQuery = ShopTagEntityQuery()
}

struct ShopWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Shop Widget"
    @Parameter(title: "Tags", default: [])
    var tags: [ShopTagEntity]?
    @Parameter(title: "Match Mode", default: .any)
    var matchMode: WidgetMatchModeAppEnum
}

struct ShopWidgetProvider: AppIntentTimelineProvider {
    func timeline(for configuration: ShopWidgetConfigurationIntent, in context: Context) async -> Timeline<ShopWidgetEntry> {
        let snapshot = WidgetSnapshotStore.load()
        let selected = Set((configuration.tags ?? []).map(\.id))
        let mode: WidgetTagMatchMode = configuration.matchMode == .all ? .all : .any
        let active = WidgetItemFilter.filtered(items: snapshot.items, selectedTagIDs: selected, matchMode: mode)
        let recent = WidgetItemFilter.filtered(items: snapshot.recentlyCompleted, selectedTagIDs: selected, matchMode: mode)
        let entry = ShopWidgetEntry(date: .now, items: active, recentlyCompleted: recent)
        return Timeline(entries: [entry], policy: .after(BackgroundSyncSchedule.nextEarliestBeginDate()))
    }
}
```

- [ ] **Step 2: Switch widget config**

```swift
AppIntentConfiguration(kind: kind, intent: ShopWidgetConfigurationIntent.self, provider: ShopWidgetProvider()) { entry in
    ShopWidgetEntryView(entry: entry)
}
```

- [ ] **Step 3: Build widget targets**

```bash
cd "/Users/wangshaoyan/code/shop!" && xcodegen generate
xcodebuild -scheme ShopWidget -destination 'generic/platform=iOS' -configuration Debug build
```

Expected: `BUILD SUCCEEDED`.

---

### Task 7: Widget UI layout + complete/restore intents

**Files:**
- Modify: `Widgets/Shared/ShopWidget.swift`

**Interfaces:**
- Consumes: filter display helpers, snapshot APIs
- Produces: `CompleteItemIntent`, `RestoreItemIntent`, redesigned `ShopWidgetEntryView`

- [ ] **Step 1: Caps by family**

```swift
private var activeCap: Int {
    switch family {
    case .systemSmall: 2
    case .systemMedium: 4
    case .systemLarge: 8
    default: 4
    }
}
private var recentCap: Int {
    switch family {
    case .systemLarge: 3
    default: 1
    }
}
private var namedTagLimit: Int {
    family == .systemSmall ? 1 : 3
}
```

- [ ] **Step 2: Layout rules**
- Small: no `ShopStrings.appName`; count + `Link`/`widgetURL` to `shop://add`.
- Medium/Large: brand title + count + add.
- Rows: complete button; name; `WidgetTagRow` using `WidgetTagDisplay`.
- Recently completed section with title (medium/large) and restore buttons.
- No trailing `Spacer` that creates a large empty middle; use tight `VStack` spacing.
- Empty / filter-empty copy from Task 5.

- [ ] **Step 3: Intents**

```swift
struct RestoreItemIntent: AppIntent {
    @Parameter(title: "Item ID") var itemID: String
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: itemID) else { return .result() }
        WidgetSnapshotStore.restoreInSnapshot(itemID: id)
        BackgroundSyncRequest.coalesceSchedule() // Task 8 stub or real
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
```

Update `CompleteItemIntent` to move into recentlyCompleted (Task 1 API) + coalesce schedule.

Add accessibility labels per spec.

- [ ] **Step 4: Build ShopWidget + ShopMacWidget**

---

### Task 8: Coalesced background sync request API

**Files:**
- Create: `Shared/Sources/ShopCore/Widgets/BackgroundSyncRequest.swift`
- Modify: widget intents to call it
- Test: unit-testable schedule state (needsSync + lastRequestAt) without requiring BGTaskScheduler in tests

**Interfaces:**
- Produces: `BackgroundSyncRequest.noteWidgetMutation()` → sets needsSync; records timestamp
- Platform hosts observe and submit real scheduler requests

Because `BGTaskScheduler` is unavailable on macOS and awkward in unit tests, keep ShopCore API pure:

```swift
public enum BackgroundSyncRequest {
    public static func noteWidgetMutation() {
        WidgetSnapshotStore.markNeedsSync()
    }
}
```

Host apps:
- On become active / enter background / after handling BG task: if `needsSync` OR regular schedule due → sync + clear on success.
- Widget cannot run WebDAV; it only sets the flag. Host must also **eagerly submit** a BG refresh with `earliestBeginDate = Date()` when possible.

iOS host helper (in app target, not ShopCore if BackgroundTasks import is painful cross-platform):

```swift
enum ShopBackgroundRefresh {
    static let taskID = "com.ryanstarfox.shop.refresh"
    static func register(handler: @escaping (BGAppRefreshTask) -> Void) { … }
    static func schedule(earliest: Date = BackgroundSyncSchedule.nextEarliestBeginDate()) {
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = earliest
        try? BGTaskScheduler.shared.submit(request) // replaces previous same id
    }
    static func scheduleSoon() { schedule(earliest: Date()) }
}
```

Widget Intent after mutation: set needsSync (ShopCore) + optionally attempt scheduleSoon via a small shared helper behind `#if canImport(BackgroundTasks) && os(iOS)`.

- [ ] **Step 1: Implement noteWidgetMutation + iOS schedule helper**
- [ ] **Step 2: Test needsSync coalescing already covered in Task 1**

---

### Task 9: iOS deep link + BGAppRefresh wiring

**Files:**
- Modify: `iOS/Shop/Info.plist` — URL types + `BGTaskSchedulerPermittedIdentifiers` + `UIBackgroundModes` = `fetch`
- Modify: `iOS/Shop/ShopApp.swift` — `onOpenURL`, register/schedule BG tasks, apply mutations, sync
- Modify: `project.yml` if Info.plist keys are generated there instead

**Interfaces:**
- URL: `shop://add`
- Task ID: `com.ryanstarfox.shop.refresh`

- [ ] **Step 1: Info.plist**

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array><string>shop</string></array>
    <key>CFBundleURLName</key>
    <string>com.ryanstarfox.shop</string>
  </dict>
</array>
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
  <string>com.ryanstarfox.shop.refresh</string>
</array>
<key>UIBackgroundModes</key>
<array>
  <string>fetch</string>
</array>
```

- [ ] **Step 2: Register in `init`/`App` before scene**

```swift
init() {
    // existing store setup…
    ShopBackgroundRefresh.register { task in
        Task { @MainActor in
            // grab shared services carefully — prefer posting NotificationCenter
            // or storing weak refs; simplest: NotificationCenter.default.post(name: .shopBackgroundRefresh)
            task.expirationHandler = { task.setTaskCompleted(success: false) }
        }
    }
}
```

Prefer a small `BackgroundSyncRunner` owned by `ShopApp` that:
1. `applyPendingWidgetMutations()`
2. `await syncCoordinator.syncNowIfConfigured()`
3. on success `WidgetSnapshotStore.clearNeedsSync()`
4. `publishWidgetSnapshot()` + reload timelines
5. `ShopBackgroundRefresh.schedule()` next interval
6. `task.setTaskCompleted(success:)`

- [ ] **Step 3: Deep link**

```swift
@State private var presentAddFromWidget = false
// ContentView / root:
.onOpenURL { url in
    guard url.scheme == "shop", url.host == "add" else { return }
    presentAddFromWidget = true
}
.sheet(isPresented: $presentAddFromWidget) {
    // existing ItemEditorView add mode
}
```

- [ ] **Step 4: scenePhase**
- `.active`: apply mutations, syncNowIfConfigured, publish, clear needsSync on success, schedule next
- `.background`: ensure schedule exists; if needsSync → `scheduleSoon()`

- [ ] **Step 5: Build iOS Shop scheme**

---

### Task 10: macOS deep link + NSBackgroundActivityScheduler

**Files:**
- Modify: `macOS/ShopMac/Info.plist` — URL scheme
- Modify: `macOS/ShopMac/ShopMacApp.swift` — openURL, background activity, apply mutations
- Modify: draft/add presentation path used by Mac FAB so widget can reuse it

**Interfaces:**
- Same `shop://add`
- Activity identifier: `com.ryanstarfox.shop.mac.refresh`

- [ ] **Step 1: Schedule activity**

```swift
let activity = NSBackgroundActivityScheduler(identifier: "com.ryanstarfox.shop.mac.refresh")
activity.interval = 3600 // scheduler will still use our nextEarliestBeginDate when rescheduling inside handler
activity.repeats = true
activity.qualityOfService = .utility
activity.schedule { completion in
    Task { @MainActor in
        // apply mutations + syncNowIfConfigured + publish + clear needsSync on success
        // then set activity.interval from BackgroundSyncSchedule delta
        completion(.finished)
    }
}
```

Note Mac limitation from spec: activity stops if user quits app; next launch syncs immediately.

- [ ] **Step 2: Wire `onOpenURL` to existing add/draft flow** (`presentAddFromWidget` / start draft)

- [ ] **Step 3: Build ShopMac + ShopMacWidget**

---

### Task 11: End-to-end verification

**Files:** none new (manual + automated)

- [ ] **Step 1: Unit tests**

```bash
cd "/Users/wangshaoyan/code/shop!/Shared" && swift test
```

Expected: all PASS, including new widget/schedule suites.

- [ ] **Step 2: Generate + build**

```bash
cd "/Users/wangshaoyan/code/shop!" && xcodegen generate
xcodebuild -scheme Shop -destination 'generic/platform=iOS' -configuration Debug build
xcodebuild -scheme ShopMac -destination 'platform=macOS' -configuration Debug build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Manual checklist (device/simulator)**
- [ ] Small widget: no app title; 1 named tag + color dots; 1 recent; `+` opens add
- [ ] Medium/Large: title; ≤3 named tags; recent counts 1 / 3
- [ ] Edit Widget: multi-select tags + OR/AND; two widgets differ
- [ ] Complete → appears in recent; Restore → back to active
- [ ] Rapid 3 completes → single needsSync; opening app syncs once and clears queues
- [ ] Dark mode readability

---

## Spec coverage self-check

| Spec section | Task(s) |
|--------------|---------|
| Snapshot enrichment | 1, 4 |
| Layout by size / tag collapse / recent | 2, 7 |
| Complete + restore queues | 1, 4, 7 |
| Deep-link add | 9, 10 |
| Per-instance filter OR/AND | 2, 6 |
| Background day 1h / night 3h | 3, 8, 9, 10 |
| Coalesced widget sync request | 1, 8 |
| Localization / a11y | 5, 7 |
| Empty/error edges | 7, 11 |

## Placeholder scan

No TBD/TODO left in task steps; platform-specific BG scheduling is spelled out with identifiers and file paths.

## Type consistency

- `WidgetTagMatchMode` (ShopCore) ↔ `WidgetMatchModeAppEnum` (widget) mapped in provider
- `applyPendingWidgetMutations()` replaces completion-only API at app call sites
- `TagInfo.id` required on new publishes; filter uses UUID identity
