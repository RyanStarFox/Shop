import SwiftUI

/// Persisted via AppStorage key `appearance_mode`.
public enum AppearancePreference: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    public init(storageValue: String) {
        self = AppearancePreference(rawValue: storageValue) ?? .system
    }

    /// `nil` means follow the system appearance.
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
