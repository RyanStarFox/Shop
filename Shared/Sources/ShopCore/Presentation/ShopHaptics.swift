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
        NSHapticFeedbackManager.defaultPerformer.perform(
            .levelChange,
            performanceTime: .now
        )
        #endif
    }

    /// Lighter feedback when restoring an item to the active list.
    public static func itemRestored() {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.prepare()
        generator.impactOccurred(intensity: 0.7)
        #elseif os(watchOS)
        WKInterfaceDevice.current().play(.click)
        #elseif os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(
            .generic,
            performanceTime: .now
        )
        #endif
    }
}
