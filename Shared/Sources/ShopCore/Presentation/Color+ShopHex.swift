import SwiftUI

public extension Color {
    init?(shopHex: String) {
        let value = shopHex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let rgb = UInt64(value, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            opacity: 1
        )
    }
}

public extension Tag {
    var displayColor: Color {
        Color(shopHex: colorHex) ?? .blue
    }
}
