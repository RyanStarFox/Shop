import Foundation

/// Marks that the host app should sync soon after widget mutations.
/// Host apps coalesce real BG / activity requests around `needsSync`.
public enum BackgroundSyncRequest {
    public static func noteWidgetMutation() {
        WidgetSnapshotStore.markNeedsSync()
    }
}
