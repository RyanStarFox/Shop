#if canImport(UIKit)
import UIKit
public typealias PlatformColor = UIColor
#elseif canImport(AppKit)
import AppKit
public typealias PlatformColor = NSColor
#elseif canImport(WatchKit)
import WatchKit
public typealias PlatformColor = UIColor
#endif

extension PlatformColor {
    public convenience init?(hex: String) {
        let r, g, b, a: CGFloat
        let start = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard start.count == 6 || start.count == 8 else { return nil }

        var hexNumber: UInt64 = 0
        guard Scanner(string: start).scanHexInt64(&hexNumber) else { return nil }

        if start.count == 8 {
            r = CGFloat((hexNumber & 0xff000000) >> 24) / 255
            g = CGFloat((hexNumber & 0x00ff0000) >> 16) / 255
            b = CGFloat((hexNumber & 0x0000ff00) >> 8) / 255
            a = CGFloat(hexNumber & 0x000000ff) / 255
        } else {
            r = CGFloat((hexNumber & 0xff0000) >> 16) / 255
            g = CGFloat((hexNumber & 0x00ff00) >> 8) / 255
            b = CGFloat(hexNumber & 0x0000ff) / 255
            a = 1.0
        }
        self.init(red: r, green: g, blue: b, alpha: a)
    }

    public var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
