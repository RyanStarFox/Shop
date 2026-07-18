import Foundation

#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

#if os(watchOS)
import WatchKit
#endif

#if os(macOS)
import AppKit
#endif

/// Cross-platform completion / restore haptic cues.
@MainActor
public enum ShopHaptics {
    /// Celebratory feedback when an item is marked complete / purchased.
    public static func itemCompleted() {
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
        #elseif os(watchOS)
        WKInterfaceDevice.current().play(.success)
        #elseif os(macOS)
        performMacPulse()
        #endif
    }

    /// Lighter feedback when restoring an item to the active list.
    public static func itemRestored() {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred(intensity: 1.0)
        #elseif os(watchOS)
        WKInterfaceDevice.current().play(.click)
        #elseif os(macOS)
        performMacPulse()
        #endif
    }

    /// Trackpad click when pull-to-refresh crosses the arm threshold.
    public static func pullToRefreshArmed() {
        #if os(macOS)
        performMacPulse()
        #endif
    }

    /// Trackpad feedback when a refresh / sync is committed.
    public static func pullToRefreshTriggered() {
        #if os(macOS)
        performMacPulse()
        #endif
    }

    #if os(macOS)
    private static func performMacPulse() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .levelChange,
            performanceTime: .now
        )
    }
    #endif
}
