# Shop!

A bilingual (English / 简体中文) shopping list for iPhone, iPad, Apple Watch, and Mac. The UI uses calm system Materials with an optional Liquid Glass treatment on newer OS versions, plus system / light / dark appearance modes.

## Features

- **Multi-platform** – Native SwiftUI targets for iOS, watchOS, and macOS sharing one `ShopCore` package
- **WatchConnectivity sync** – iPhone ↔ Apple Watch via reachable messages, application context, and file transfers when payloads are large
- **WebDAV sync** – iPhone / Mac sync through a versioned `shop_sync.json` snapshot, ETag conditional writes, and Keychain-stored passwords (HTTPS by default)
- **Automatic + manual sync** – Debounced automatic passes after local edits, plus an explicit Sync Now action
- **Tags** – Color-coded tags with management on iPhone and Mac; Watch can select existing tags when adding items
- **Inline archive** – Completed items stay in the same scroll view beneath the active list
- **One-level undo** – Completion, restore, and soft-delete actions present a short-lived undo affordance
- **Local-first SwiftData** – Persistence is local; cloud sync is WebDAV and WatchConnectivity only (no CloudKit)

## Project Structure

```
Shop!/
├── Shared/                     # Swift Package – ShopCore (models, store, sync, theme, undo)
├── iOS/Shop/                   # iPhone / iPad app
├── watchOS/ShopWatch/          # Apple Watch companion
├── macOS/ShopMac/              # Mac split-view app
├── project.yml                 # XcodeGen project spec
└── README.md
```

## Requirements

- Xcode 16+ (Xcode 26 tooling works with the current project)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- macOS 15.0+, iOS 18.0+, watchOS 11.0+

## Generate the Xcode Project

```bash
brew install xcodegen
cd "Shop!"
xcodegen generate
open Shop.xcodeproj
```

## Schemes and Build Commands

| Scheme | Platform | Notes |
|--------|----------|-------|
| `Shop` | iOS | Embeds `ShopWatch` |
| `ShopMac` | macOS | Three-column split view |
| `ShopWatch` | watchOS | Companion UI |

Unsigned local builds:

```bash
xcodebuild -scheme Shop -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build

xcodebuild -scheme ShopMac -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build

xcodebuild -scheme ShopWatch -destination 'generic/platform=watchOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

Shared package tests:

```bash
cd Shared && swift test
```

## Sync Setup

### iPhone ↔ Apple Watch

Uses WatchConnectivity. Delivery is best when the companion is reachable; application context and queued file transfers provide eventual consistency when devices reconnect. Bluetooth / proximity matter more than “same Wi‑Fi” alone.

### iPhone / Mac ↔ WebDAV

1. Open **Settings → WebDAV**
2. Enter an HTTPS server URL (HTTP only if explicitly allowed in advanced configuration)
3. Enter username and password — the password is stored in Keychain, not UserDefaults
4. Use **Sync Now**, or rely on automatic debounced sync after edits

Typical endpoints include Nextcloud, ownCloud, and Synology WebDAV folders. The remote document is `shop_sync.json`. Shop apps configure HTTPS-only WebDAV by default.

## Architecture

```
SwiftData (ModelContainer)
  └── ShoppingStore / DataStore
       ├── SnapshotMerger (last-write-wins + tombstones + device-ID tie-break)
       ├── SyncCoordinator (debounce, single-flight, 412 retries)
       ├── WatchConnectivityTransport (iPhone ↔ Watch)
       └── WebDAVTransport + KeychainStore (iPhone / Mac ↔ server)
```

## Localization

User-facing strings live in:

- `Shared/Sources/ShopCore/Resources/{en,zh-Hans}.lproj` (ShopCore)
- Platform `Localizable.strings` for target-specific copy

Access shared strings through `ShopStrings`.

## Verification Status

Automated gates on this branch:

- `cd Shared && swift test` — 91 tests passed
- Unsigned builds for `Shop`, `ShopMac`, and `ShopWatch` succeeded
- Static checks: no whitespace errors; no hardcoded English `Text`/`TextField` labels in platform Swift; WebDAV passwords use Keychain (legacy UserDefaults key only removed during migration)

Still requiring human / hardware validation (not claimed passing):

- Simulator pass for light/dark/system appearance, largest Dynamic Type, VoiceOver, Reduce Motion, and small/large Watch layouts
- Disposable WebDAV scenarios (first upload, merge, offline concurrent edit, 412 retry, bad credentials, timeout recovery)
- Paired iPhone ↔ Apple Watch add/complete/restore, offline delivery, reconnect, and idempotency
- Optional follow-up: physical tombstone purge after successful sync past retention (snapshots currently retain soft-deleted records)

## License

MIT
