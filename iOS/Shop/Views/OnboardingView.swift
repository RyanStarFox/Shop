import SwiftUI
import ShopCore

struct OnboardingView: View {
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
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, pageContent in
                    VStack(spacing: ShopTheme.spacingMD) {
                        Image(systemName: pageContent.symbol)
                            .font(.system(size: 48, weight: .semibold))
                            .foregroundStyle(ShopTheme.brandColor)
                        Text(pageContent.title)
                            .font(.title2.weight(.bold))
                            .multilineTextAlignment(.center)
                        Text(pageContent.body)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .tag(index)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .always))
            #endif

            Button {
                if page < pages.count - 1 {
                    page += 1
                } else {
                    onFinished()
                }
            } label: {
                Text(page < pages.count - 1 ? ShopStrings.onboardingNext : ShopStrings.onboardingGetStarted)
                    .frame(maxWidth: 280)
            }
            .buttonStyle(.borderedProminent)
            .tint(ShopTheme.brandColor)
            .padding(.bottom, ShopTheme.spacingMD)
        }
        .padding()
    }
}
