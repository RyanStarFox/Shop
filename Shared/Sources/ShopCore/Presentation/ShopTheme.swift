import SwiftUI

public enum ShopTheme {
    /// Brand accent color (shopping-cart logo).
    public static let brandColor = Color(shopHex: "#C53A32") ?? .red

    public static let spacingXS: CGFloat = 4
    public static let spacingSM: CGFloat = 8
    public static let spacingMD: CGFloat = 16
    public static let spacingLG: CGFloat = 24

    public static let minTouchTarget: CGFloat = 44
    public static let rowCornerRadius: CGFloat = 12
}
