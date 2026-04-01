import SwiftUI

struct SettingsShortcutPage: View {
    @ObservedObject var model: AppModel
    @Environment(\.topCardHeight) private var topCardHeight
    @Environment(\.openURL) private var openURL
    @Environment(\.appTheme) private var theme

    private let shortcutURL = URL(string: "https://www.icloud.com/shortcuts/e32b44858d5f4c829b35c9f8ad5f2756")!

    var body: some View {
        ZStack {
            SettingsGradientBG(model: model)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    DetailHeader(title: String(localized: "Wallpaper", comment: "Settings section title"))

                    VStack(alignment: .leading, spacing: 12) {
                    Text(String(localized: "Set today's energy canvas as your Lock Screen wallpaper automatically each time you close the app."))
                        .font(.subheadline)
                        .foregroundColor(theme.adaptiveSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "1. Tap the button to add the wallpaper shortcut"))
                        Text(String(localized: "2. Open Shortcuts → Automation → + → App"))
                        Text(String(localized: "3. Select this app, pick \"Is Closed\""))
                        Text(String(localized: "4. Set the action to the wallpaper shortcut"))
                        Text(String(localized: "5. Turn off \"Ask Before Running\""))
                    }
                    .font(.caption)
                    .foregroundColor(theme.adaptiveSecondaryText)

                    Button {
                        openURL(shortcutURL)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.caption.weight(.semibold))
                            Text(String(localized: "Get Wallpaper Shortcut"))
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(AppColors.brandAccent))
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
                .glassCard()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: topCardHeight)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
