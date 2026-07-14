# Task 6 Report — WatchConnectivity Device Sync

## Delivered

- Added a SwiftPM-testable `WatchSnapshotHandler` that decodes Watch snapshots and merges them through the existing `SnapshotMerger`.
- Added WatchConnectivity transport with immediate reachable delivery, application-context convergence, oversized-payload file transfer, activation/reachability/foreground triggers, and `nonisolated` delegate callbacks that only forward captured snapshots to `MainActor`.
- Changed local mutation notification to support both WebDAV and Watch observers. Remote snapshot application bypasses local-mutation observers, preventing sync echoes.
- Replaced production-facing Wi-Fi terminology with Watch sync; `WiFiSyncService` remains only as a source-compatibility typealias.
- Regenerated the Xcode project with `ShopWatch` embedded in `Shop`. The archive contains `Products/Applications/Shop.app/Watch/ShopWatch.app`.

## TDD coverage

`WatchSnapshotHandlerTests` verifies duplicate-message idempotency, newer Watch edits, newer iPhone edits, tombstone propagation, and invalid-snapshot errors. `DataStoreTests` verifies multiple local mutation observers and no remote-import echo.

## Verification

- `swift test`: 63 tests passed.
- `xcodebuild ... -scheme ShopWatch ... CODE_SIGNING_ALLOWED=NO build`: passed.
- `xcodebuild ... -scheme ShopMac ... CODE_SIGNING_ALLOWED=NO build`: passed.
- `xcodebuild ... -scheme Shop ... CODE_SIGNING_ALLOWED=NO archive`: passed.
- `git diff --check`: passed.

## Remaining validation

No paired iPhone/Apple Watch hardware session was available. Real-device WatchConnectivity timing, reachability transitions, application-context capacity, and file-transfer cleanup still require manual validation.

## Review fixes

- Snapshot receipt now reads and validates the version envelope before decoding the complete payload. Legacy v1 and current v2 are accepted; non-positive and future versions produce localized `unsupportedVersion` errors without entering `SnapshotMerger`.
- Added a platform-independent Watch message protocol. Request replies carry an immediately applicable snapshot within the safe reply budget or an explicit deferred status when file transfer is required. Missing snapshot data is rejected as an invalid reply.
- File receive failures now publish a localized `lastError`. Temporary-file deletion failures are likewise observable, and initialization/session activation remove only stale files with the dedicated `shop-watch-snapshot-` prefix.
- The WatchConnectivity delegate continues to capture only sendable values before hopping to `MainActor`; no `@preconcurrency` annotation is used.

### Review verification

- Focused handler/protocol tests: 11 passed.
- Full `swift test`: 69 tests passed.
- iOS unsigned archive: passed and includes the Watch app.
- watchOS unsigned build: passed.
- macOS unsigned build: passed.
- `git diff --check`: passed.
- Existing asset-catalog and App Intents metadata warnings remain; no Swift concurrency warnings were emitted.

Paired-device behavior remains unverified because no physical iPhone/Apple Watch pair was available.

## Final review fixes

- Watch transfer files now live in a dedicated temporary directory. Cleanup reads `outstandingFileTransfers` first, canonicalizes paths with standardization and symbolic-link resolution, and removes only service-prefixed files older than 24 hours that are not still queued.
- Local mutations now pass through an injectable 500 ms debouncer. A newer mutation cancels only the pending sleeper; once sending begins, another mutation schedules a separate follow-up send.
- Transport teardown uses an isolated deinitializer to cancel pending debounce work and unregister its local-mutation observer.

### Final review verification

- Focused cleanup/debounce/observer tests: 9 passed.
- Full `swift test`: 78 tests passed.
- iOS unsigned archive: passed and contains `ShopWatch.app`.
- watchOS unsigned build: passed.
- macOS unsigned build: passed.
- `git diff --check`: passed.
- Existing asset-catalog and App Intents metadata warnings remain; no Swift concurrency warnings were emitted.

Paired-device WatchConnectivity behavior remains unverified because physical iPhone/Apple Watch hardware was unavailable.
