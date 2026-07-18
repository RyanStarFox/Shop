import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public enum ShopHexColor {
    /// Accepts `#RRGGBB`, `RRGGBB`, `#RGB`, or `RGB` and returns uppercase `#RRGGBB`.
    public static func normalize(_ input: String) -> String? {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if value.hasPrefix("#") {
            value.removeFirst()
        }
        guard !value.isEmpty else { return nil }

        if value.count == 3 {
            value = value.map { String($0) + String($0) }.joined()
        }

        guard value.count == 6,
              value.allSatisfy(\.isHexDigit),
              let rgb = UInt64(value, radix: 16)
        else { return nil }

        _ = rgb
        return "#\(value)"
    }
}

public extension Color {
    init?(shopHex: String) {
        guard let normalized = ShopHexColor.normalize(shopHex) else { return nil }
        let value = String(normalized.dropFirst())
        guard let rgb = UInt64(value, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            opacity: 1
        )
    }

    var shopHexString: String? {
        #if canImport(UIKit)
        let uiColor = UIColor(self)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        guard uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return String(
            format: "#%02X%02X%02X",
            Int((r * 255).rounded()),
            Int((g * 255).rounded()),
            Int((b * 255).rounded())
        )
        #elseif canImport(AppKit)
        guard let rgb = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return String(
            format: "#%02X%02X%02X",
            Int((rgb.redComponent * 255).rounded()),
            Int((rgb.greenComponent * 255).rounded()),
            Int((rgb.blueComponent * 255).rounded())
        )
        #else
        return nil
        #endif
    }
}

public extension Tag {
    var displayColor: Color {
        Color(shopHex: colorHex) ?? .blue
    }
}
