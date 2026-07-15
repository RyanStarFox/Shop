import SwiftUI

public enum ShopTheme {
    /// Brand red matched to the shopping-cart logo.
    public static let brandRed = Color(shopHex: "#E0312C") ?? .red

    /// Backwards-compatible alias used across existing call sites.
    public static let naturalGreen = brandRed

    public static let spacingXS: CGFloat = 4
    public static let spacingSM: CGFloat = 8
    public static let spacingMD: CGFloat = 16
    public static let spacingLG: CGFloat = 24

    public static let minTouchTarget: CGFloat = 44
    public static let rowCornerRadius: CGFloat = 12
}
