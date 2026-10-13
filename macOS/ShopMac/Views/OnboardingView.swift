import SwiftUI
import ShopCore

struct OnboardingView: View {
    @Environment(\.shopAccent) private var shopAccent
    enum PlatformStyle {
        case phone
        case mac
    }

    let style: PlatformStyle
    let onFinished: () -> Void

    @State private var page = 0

    private var pages: [(title: String, body: String, symbol: String)] {
        switch style {
        case .phone:
            [
                (ShopStrings.onboardingAddTitle, ShopStrings.onboardingAddBodyPhone, "plus.circle.fill"),
                (ShopStrings.onboardingCompleteTitle, ShopStrings.onboardingCompleteBody, "checkmark.circle.fill"),
                (ShopStrings.onboardingSyncTitle, ShopStrings.onboardingSyncBody, "arrow.triangle.2.circlepath"),
                (ShopStrings.onboardingGesturesTitle, ShopStrings.onboardingGesturesBodyPhone, "hand.draw.fill")
            ]
        case .mac:
            [
                (ShopStrings.onboardingAddTitle, ShopStrings.onboardingAddBodyMac, "plus.circle.fill"),
                (ShopStrings.onboardingCompleteTitle, ShopStrings.onboardingCompleteBodyMac, "checkmark.circle.fill"),
                (ShopStrings.onboardingSyncTitle, ShopStrings.onboardingSyncBody, "arrow.triangle.2.circlepath"),
                (ShopStrings.onboardingGesturesTitle, ShopStrings.onboardingGesturesBodyMac, "keyboard")
            ]
        }
    }

    var body: some View {
        VStack(spacing: ShopTheme.spacingLG) {
            let pageContent = pages[page]
            VStack(spacing: ShopTheme.spacingMD) {
                Image(systemName: pageContent.symbol)
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(shopAccent)
                Text(pageContent.title)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(pageContent.body)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(page)

            HStack(spacing: 8) {
                ForEach(pages.indices, id: \.self) { index in
                    Circle()
                        .fill(index == page ? shopAccent : Color.secondary.opacity(0.35))
                        .frame(width: 7, height: 7)
                }
            }
            .accessibilityLabel("\(page + 1) / \(pages.count)")

            Button {
                if page < pages.count - 1 {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        page += 1
                    }
                } else {
                    onFinished()
                }
            } label: {
                Text(page < pages.count - 1 ? ShopStrings.onboardingNext : ShopStrings.onboardingGetStarted)
                    .frame(maxWidth: 280)
            }
            .buttonStyle(.borderedProminent)
            .tint(shopAccent)
            .padding(.bottom, ShopTheme.spacingMD)
        }
        .padding()
    }
}
