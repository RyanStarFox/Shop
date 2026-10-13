import SwiftUI

public enum ShopTheme {
    /// Default brand accent (shopping-cart logo). User-chosen accents override this at runtime.
    public static let defaultBrandHex = "#C53A32"
    public static let brandColor = Color(shopHex: defaultBrandHex) ?? .red

    public static let spacingXS: CGFloat = 4
    public static let spacingSM: CGFloat = 8
    public static let spacingMD: CGFloat = 16
    public static let spacingLG: CGFloat = 24

    public static let minTouchTarget: CGFloat = 44
    public static let rowCornerRadius: CGFloat = 12
}

private struct ShopAccentKey: EnvironmentKey {
    static let defaultValue = ShopTheme.brandColor
}

public extension EnvironmentValues {
    /// Active accent. Defaults to the brand red until Settings overrides it.
    var shopAccent: Color {
        get { self[ShopAccentKey.self] }
        set { self[ShopAccentKey.self] = newValue }
    }
}

/// Persisted theme accent. Default is the brand red; presets are system colors.
public enum ThemeAccent {
    public static let storageKey = "theme_color_hex"
    public static let defaultHex = ShopTheme.defaultBrandHex
    /// Light-mode sRGB of system blue. Stored when that preset is chosen; resolved with `Color.blue`.
    public static let systemBlueHex = "#007AFF"

    public struct Preset: Identifiable, Equatable, Sendable {
        public let id: String
        public let hex: String
    }

    public static let presets: [Preset] = [
        Preset(id: "brand", hex: defaultHex),
        Preset(id: "red", hex: "#FF3B30"),
        Preset(id: "orange", hex: "#FF9500"),
        Preset(id: "yellow", hex: "#FFCC00"),
        Preset(id: "green", hex: "#34C759"),
        Preset(id: "blue", hex: systemBlueHex),
        Preset(id: "purple", hex: "#AF52DE"),
        Preset(id: "pink", hex: "#FF2D55")
    ]

    public static func color(hex: String) -> Color {
        if isSystemBlue(hex) {
            return .blue
        }
        return Color(shopHex: hex) ?? ShopTheme.brandColor
    }

    public static func isSystemBlue(_ hex: String) -> Bool {
        matches(hex, systemBlueHex)
    }

    public static func matches(_ lhs: String, _ rhs: String) -> Bool {
        guard let left = ShopHexColor.normalize(lhs), let right = ShopHexColor.normalize(rhs) else {
            return false
        }
        return left == right
    }
}
