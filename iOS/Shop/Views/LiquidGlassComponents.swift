import SwiftUI

// MARK: - Liquid Glass Background
struct LiquidGlassBackground: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Base gradient
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [Color(hex: "1C1C1E"), Color(hex: "2C2C2E"), Color(hex: "1C1C1E")]
                        : [Color(hex: "F2F2F7"), Color(hex: "E5E5EA"), Color(hex: "F2F2F7")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                // Floating orbs for glass effect
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.accentColor.opacity(0.15), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: geometry.size.width * 0.35
                        )
                    )
                    .frame(width: geometry.size.width * 0.7)
                    .position(x: geometry.size.width * 0.8, y: geometry.size.height * 0.15)
                    .blur(radius: 30)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.purple.opacity(0.1), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: geometry.size.width * 0.3
                        )
                    )
                    .frame(width: geometry.size.width * 0.6)
                    .position(x: geometry.size.width * 0.2, y: geometry.size.height * 0.75)
                    .blur(radius: 25)
            }
        }
    }
}

// MARK: - Glass Card
struct GlassCard<Content: View>: View {
    @Environment(\.colorScheme) var colorScheme
    let content: Content
    var cornerRadius: CGFloat = 20
    var padding: CGFloat = 16

    init(
        cornerRadius: CGFloat = 20,
        padding: CGFloat = 16,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(colorScheme == .dark ? 0.15 : 0.5),
                                        .white.opacity(colorScheme == .dark ? 0.05 : 0.2)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
            }
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08),
                radius: 15, x: 0, y: 5
            )
    }
}

// MARK: - Glass Button
struct GlassButton: View {
    let title: String
    let systemImage: String?
    let action: () -> Void
    var color: Color = .accentColor
    var isFullWidth: Bool = false

    init(
        _ title: String,
        systemImage: String? = nil,
        color: Color = .accentColor,
        isFullWidth: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.color = color
        self.isFullWidth = isFullWidth
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .background {
                Capsule(style: .continuous)
                    .fill(color.gradient)
                    .shadow(color: color.opacity(0.4), radius: 8, x: 0, y: 4)
            }
        }
    }
}

// MARK: - Glass TextField
struct GlassTextField: View {
    let placeholder: String
    @Binding var text: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
            }
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                }
        }
    }
}

// MARK: - Tag Chip
struct TagChip: View {
    let tag: Tag
    var isSelected: Bool = false
    var onTap: (() -> Void)?

    var body: some View {
        Button {
            onTap?()
        } label: {
            Text(tag.name)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background {
                    Capsule(style: .continuous)
                        .fill(isSelected
                            ? tag.color.opacity(0.3)
                            : .ultraThinMaterial
                        )
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(
                                    isSelected ? tag.color : .white.opacity(0.15),
                                    lineWidth: 1
                                )
                        }
                }
                .foregroundStyle(isSelected ? tag.color : .primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Search Bar
struct SearchBar: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(ShopStrings.itemSearch, text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }
}

// MARK: - Color Extension
extension Color {
    init(hex: String) {
        let r, g, b: Double
        let start = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let scanner = Scanner(string: start)
        var hexNumber: UInt64 = 0
        guard scanner.scanHexInt64(&hexNumber) else {
            self.init(.sRGB, red: 0, green: 0, blue: 0, opacity: 1)
            return
        }
        r = Double((hexNumber & 0xff0000) >> 16) / 255
        g = Double((hexNumber & 0x00ff00) >> 8) / 255
        b = Double(hexNumber & 0x0000ff) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}
