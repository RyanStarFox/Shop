# UX Widgets Onboarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver Mac draft-add UX, editable dates on all platforms, pull-to-refresh sync, first-run onboarding (iPhone/Mac), interactive widgets (iPhone/Mac), and unify theme to `ShopTheme.brandColor` (`#C53A32`).

**Architecture:** Keep ShopCore as the shared source of truth. UI platforms call `DataStore` / `SyncCoordinator`. Widgets share data via App Group + App Intents. Mac draft state stays in view `@State` until confirmed. Theme is a single `brandColor` token.

**Tech Stack:** SwiftUI, SwiftData, WidgetKit, AppIntents, XcodeGen (`project.yml`), ShopCore package.

## Global Constraints

- Min versions: iOS 18 / macOS 15 / watchOS 11.
- Theme token: `ShopTheme.brandColor` = `#C53A32`; delete `brandRed` / `naturalGreen`.
- Watch: pull-to-refresh only for sync; no onboarding; no widgets; dates editable with crown `DatePicker`.
- Widgets: active (pending) items only; complete removes row and next item fills; dark mode; empty state opens app.
- Mac draft: discard on other selection / re-add / window close if name empty.
- Commits: only when user asks, or per-task if user previously approved frequent commits — default: batch at natural checkpoints unless asked.

---

## File Structure

| Path | Responsibility |
|------|----------------|
| `Shared/.../ShopTheme.swift` | `brandColor` only |
| `Shared/.../DataStore.swift` + `ShoppingStore.swift` | `addItem(..., createdAt:)` |
| `macOS/ShopMac/ContentView.swift` | Draft add, FAB, selection, keys, haptics, refresh, dates |
| `iOS/Shop/Views/ItemEditorView.swift` | Persist createdAt on add |
| `iOS/Shop/...` | Onboarding, refreshable, settings entry |
| `watchOS/ShopWatch/...` | Date pickers, refreshable, edit sheet |
| `Widgets/` (new) | Shared widget UI + intents |
| `project.yml` | Widget targets + App Group entitlements |

---

### Task 1: Theme → `brandColor` (`#C53A32`)

**Files:**
- Modify: `Shared/Sources/ShopCore/Presentation/ShopTheme.swift`
- Modify: all call sites of `brandRed` / `naturalGreen` / `#E0312C` (iOS, macOS, watchOS, Shared)
- Test: build Shop / ShopMac / ShopWatch

**Interfaces:**
- Produces: `ShopTheme.brandColor: Color`

- [ ] **Step 1:** Replace theme definition:

```swift
public enum ShopTheme {
    public static let brandColor = Color(shopHex: "#C53A32") ?? .red
    // spacing constants unchanged…
}
```

- [ ] **Step 2:** Replace every `ShopTheme.brandRed` and `ShopTheme.naturalGreen` with `ShopTheme.brandColor`. Replace default tag hex `#E0312C` with `#C53A32` where it is the brand default.

- [ ] **Step 3:** Build:

```bash
cd "/Users/wangshaoyan/code/shop!" && xcodegen generate
xcodebuild -scheme Shop -destination 'generic/platform=iOS' -configuration Debug build
```

Expected: `BUILD SUCCEEDED`, no references to `brandRed`/`naturalGreen`.

---

### Task 2: `addItem` accepts optional `createdAt`

**Files:**
- Modify: `Shared/Sources/ShopCore/Storage/ShoppingStore.swift` (`addItem`)
- Modify: `Shared/Sources/ShopCore/Storage/DataStore.swift` (`addItem`)
- Test: `Shared/Tests/ShopCoreTests/DataStoreTests.swift` or `ShoppingStoreTests.swift`

**Interfaces:**
- Produces:
  - `ShoppingStore.addItem(name:tagIDs:createdAt:now:) throws -> ShoppingItem`
  - `DataStore.addItem(name:tags:createdAt:)`

- [ ] **Step 1:** Add failing test that `addItem(name:tags:createdAt:)` persists the provided date (not `Date()`).

- [ ] **Step 2:** Extend store:

```swift
public func addItem(
    name: String,
    tagIDs: [UUID],
    createdAt: Date? = nil,
    now: Date = Date()
) throws -> ShoppingItem {
    let stamp = createdAt ?? now
    // ShoppingItem(createdAt: stamp, updatedAt: now, …)
}
```

Wire `DataStore.addItem(name:tags:createdAt: Date? = nil)`.

- [ ] **Step 3:** Run `swift test` in `Shared` or Xcode `ShopCoreTests`. Expected: PASS.

---

### Task 3: Mac draft add + FAB + ⌘N / ⌘Z + selection + space/return + haptics

**Files:**
- Modify: `macOS/ShopMac/ContentView.swift` (major)
- Possibly extract: `macOS/ShopMac/Views/MacDraftDetailView.swift` if ContentView grows too large

**Interfaces:**
- Consumes: `DataStore.addItem(name:tags:createdAt:)`, `ShopHaptics`, `UndoCoordinator`
- Produces: draft state `isDrafting` / `draftName` / `draftTags` / `draftCreatedAt`; FAB; keyboard handlers

- [ ] **Step 1:** Remove `quickAddBar` from sidebar. Add bottom-trailing FAB overlay on content column.

- [ ] **Step 2:** On FAB / ⌘N: set `isDrafting = true`, clear draft fields (`draftCreatedAt = Date()`), select a sentinel (e.g. `selectedItemID = nil` + `isDrafting`), insert placeholder row at top of active list.

- [ ] **Step 3:** Detail pane: if `isDrafting`, show same form as edit (name, tags, createdAt DatePicker). On non-empty name save → `addItem` → `isDrafting = false`, select new id. Discard draft when selecting another item, pressing FAB again, or window close with empty name.

- [ ] **Step 4:** Replace `List(selection:)` with tap-to-select on rows; keep `listRowBackground` with `brandColor.opacity(0.12)`.

- [ ] **Step 5:** `.onKeyPress` / local keyboard monitors for Space/Return when not text-focused → toggle completion + `ShopHaptics`. Bind ⌘Z to undo, ⌘N to start draft.

- [ ] **Step 6:** Call `ShopHaptics.itemCompleted()` / `.itemRestored()` in Mac toggle completion path.

- [ ] **Step 7:** Build ShopMac. Manual smoke: draft discard, confirm save, keys, highlight.

---

### Task 4: Editable dates — iPhone + Mac + Watch

**Files:**
- Modify: `iOS/Shop/Views/ItemEditorView.swift` — pass `createdAt` on add; show dates section for add mode too
- Modify: Mac detail (Task 3) — DatePickers already planned
- Modify: `watchOS/ShopWatch/Views/WatchAddItemView.swift` — createdAt DatePicker
- Create: `watchOS/ShopWatch/Views/WatchEditItemView.swift` — edit dates (+ optional name)
- Modify: `watchOS/ShopWatch/ContentView.swift` — navigation to edit

**Interfaces:**
- Consumes: `addItem(..., createdAt:)`, `updateItem(..., createdAt:completedAt:updateCompletedAt:)`

- [ ] **Step 1:** iPhone `save()` for `.add` calls `dataStore.addItem(name:tags:createdAt: createdAt)`. Show dates DisclosureGroup in add mode (createdAt only).

- [ ] **Step 2:** Mac detail DatePickers bind to `updateItem` on change.

- [ ] **Step 3:** Watch add: `@State createdAt = Date()`, DatePicker, pass to `addItem`.

- [ ] **Step 4:** Watch edit sheet from row: DatePickers for createdAt / completedAt if completed; save via `updateItem`.

- [ ] **Step 5:** Build three schemes.

---

### Task 5: Pull-to-refresh sync (all platforms)

**Files:**
- Modify: `iOS/Shop/Views/ItemListView.swift` or `ContentView.swift`
- Modify: `macOS/ShopMac/ContentView.swift` list
- Modify: `watchOS/ShopWatch/ContentView.swift`

**Interfaces:**
- Consumes: `SyncCoordinator.syncNowIfConfigured()`, `WatchSyncService` request/send

- [ ] **Step 1:** iOS list `.refreshable { await syncCoordinator.syncNowIfConfigured() }`

- [ ] **Step 2:** Mac list same.

- [ ] **Step 3:** Watch `.refreshable { watchSync.requestLatestSnapshot(); watchSync.sendLatestSnapshot() }` (or existing sync API).

---

### Task 6: First-run onboarding (iPhone + Mac)

**Files:**
- Create: `iOS/Shop/Views/OnboardingView.swift`
- Create: `macOS/ShopMac/Views/MacOnboardingView.swift` (or shared SwiftUI if identical structure)
- Modify: settings views — “查看教程” button
- Modify: `ShopApp.swift` / `ShopMacApp.swift` — present when `!hasSeenOnboarding`
- Modify: localization strings en + zh-Hans

**Interfaces:**
- Produces: `@AppStorage("has_seen_onboarding")` / `ShopStrings` onboarding keys

- [ ] **Step 1:** Add strings for 4 pages (add, complete, WebDAV, gestures/shortcuts — platform-specific body text).

- [ ] **Step 2:** TabView / page control onboarding; Done sets `hasSeenOnboarding = true`.

- [ ] **Step 3:** Auto-present once on launch; Settings reopens sheet/window.

---

### Task 7: Widgets (iPhone + Mac) — App Group + complete intent

**Files:**
- Create: `Widgets/ShopWidgetBundle.swift`, `ShopWidget.swift`, `CompleteItemIntent.swift`, `WidgetDataProvider.swift`
- Modify: `project.yml` — `ShopWidget` (iOS), `ShopMacWidget` (macOS), App Group `group.com.ryanstarfox.shop`
- Modify: iOS/Mac entitlements + Info.plist as needed
- Modify: `DataStore` / app lifecycle to publish active-item snapshot for widgets and reload timelines after mutations

**Interfaces:**
- Produces: `CompleteItemIntent(itemID: UUID)` → marks complete, reloads widgets
- Provider reads pending items from App Group store

- [ ] **Step 1:** Add App Group to Shop, ShopMac, widget targets in `project.yml` + entitlements.

- [ ] **Step 2:** Shared snapshot writer: on `DataStore` mutation / app active, write JSON of active items (id, name, sortOrder) to App Group container; `WidgetCenter.shared.reloadAllTimelines()`.

- [ ] **Step 3:** Widget UI: small/medium/large family; list rows with Button(intent:); empty state; light/dark via system materials + `brandColor`.

- [ ] **Step 4:** `CompleteItemIntent` opens shared store / performs complete via ShopCore helper that can run in extension (prefer App Group JSON + a small Shared sync path, or open URL to app if extension cannot mutate SwiftData — prefer in-extension mutation if App Group store supports it).

- [ ] **Step 5:** After complete, rewrite snapshot (item gone, next items fill), reload timelines.

- [ ] **Step 6:** `xcodegen generate` + build Shop + ShopMac with widgets embedded.

**Note:** If SwiftData cannot be opened safely from the extension, use App Group JSON as source of truth for the widget and have the intent write a “pending completion” queue that the main app drains on launch — document choice in code comment and keep UX: complete disappears immediately from widget UI optimistically.

---

### Task 8: Verification

- [ ] Run ShopCore tests.
- [ ] Build Shop, ShopMac, ShopWatch.
- [ ] Grep: no `brandRed`/`naturalGreen`; theme hex is `#C53A32`.
- [ ] Manual checklist from spec §测试计划.

---

## Spec coverage self-check

| Spec section | Task |
|--------------|------|
| brandColor `#C53A32` | 1 |
| Mac draft add / FAB / ⌘N / discard | 3 |
| Selection highlight / space-return / haptics / ⌘Z | 3 |
| Dates iPhone/Mac/Watch | 2, 4 |
| Pull refresh | 5 |
| Onboarding | 6 |
| Widgets + dark + empty | 7 |
| WebDAV password note | docs only (already true) |

## Placeholder scan

No TBD steps; widget SwiftData-vs-JSON fallback is an explicit decision point in Task 7 Step 4.
