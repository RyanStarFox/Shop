import SwiftUI
import ShopCore

// MARK: - Background

struct ShopSurfaceBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if #available(iOS 26, *) {
                Color.clear
                    .background(.background)
            } else {
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [Color(shopHex: "1C1C1E") ?? .black, Color(shopHex: "2C2C2E") ?? .black]
                        : [Color(shopHex: "F2F2F7") ?? .white, Color(shopHex: "ECECEF") ?? .white],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
    }
}

struct LiquidGlassBackground: View {
    var body: some View {
        ShopSurfaceBackground()
    }
}

// MARK: - Glass Surfaces

extension View {
    @ViewBuilder
    func shopGlassSurface<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26, *) {
            self
                .glassEffect(.regular, in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay {
                    shape.stroke(.white.opacity(0.12), lineWidth: 0.5)
                }
        }
    }

    @ViewBuilder
    func shopInteractiveGlassSurface<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26, *) {
            self
                .glassEffect(.regular.interactive(), in: shape)
        } else {
            shopGlassSurface(in: shape)
        }
    }
}

// MARK: - Glass Card

struct GlassCard<Content: View>: View {
    let content: Content
    var cornerRadius: CGFloat = ShopTheme.rowCornerRadius
    var padding: CGFloat = ShopTheme.spacingMD

    init(
        cornerRadius: CGFloat = ShopTheme.rowCornerRadius,
        padding: CGFloat = ShopTheme.spacingMD,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .shopGlassSurface(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Primary Button

struct GlassButton: View {
    let title: String
    let systemImage: String?
    let action: () -> Void
    var isFullWidth: Bool = false

    init(
        _ title: String,
        systemImage: String? = nil,
        isFullWidth: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isFullWidth = isFullWidth
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: ShopTheme.spacingXS) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, ShopTheme.spacingMD)
            .padding(.vertical, ShopTheme.spacingSM + 4)
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .frame(minHeight: ShopTheme.minTouchTarget)
            .background(ShopTheme.naturalGreen.gradient, in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Text Field

struct GlassTextField: View {
    let placeholder: String
    @Binding var text: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: ShopTheme.spacingSM) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
            }
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, ShopTheme.spacingMD)
        .padding(.vertical, ShopTheme.spacingSM + 4)
        .shopGlassSurface(in: RoundedRectangle(cornerRadius: ShopTheme.rowCornerRadius, style: .continuous))
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
                .lineLimit(1)
                .padding(.horizontal, ShopTheme.spacingSM + 4)
                .padding(.vertical, ShopTheme.spacingXS + 2)
                .background {
                    Capsule(style: .continuous)
                        .fill(
                            isSelected
                                ? AnyShapeStyle(tag.displayColor.opacity(0.2))
                                : AnyShapeStyle(.quaternary.opacity(0.4))
                        )
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(
                                    isSelected ? tag.displayColor : .clear,
                                    lineWidth: 1
                                )
                        }
                }
                .foregroundStyle(isSelected ? tag.displayColor : .primary)
        }
        .buttonStyle(.plain)
        .frame(minHeight: ShopTheme.minTouchTarget)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel(tag.name)
    }
}

// MARK: - Search Bar

struct SearchBar: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: ShopTheme.spacingSM) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(ShopStrings.itemSearch, text: $text)
                .textFieldStyle(.plain)
                .accessibilityLabel(ShopStrings.itemSearch)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(minWidth: ShopTheme.minTouchTarget, minHeight: ShopTheme.minTouchTarget)
                .accessibilityLabel(ShopStrings.filterReset)
            }
        }
        .padding(.horizontal, ShopTheme.spacingMD)
        .padding(.vertical, ShopTheme.spacingSM)
        .shopGlassSurface(in: RoundedRectangle(cornerRadius: ShopTheme.rowCornerRadius, style: .continuous))
    }
}
