import SwiftUI

struct SettingsShortcutPage: View {
    @ObservedObject var model: AppModel
    @Environment(\.topCardHeight) private var topCardHeight
    @Environment(\.openURL) private var openURL
    @Environment(\.appTheme) private var theme

    private let shortcutURL = URL(string: "https://www.icloud.com/shortcuts/e32b44858d5f4c829b35c9f8ad5f2756")!

    private let steps: [(number: String, text: LocalizedStringKey)] = [
        ("1", "Tap the button below to add the wallpaper shortcut"),
        ("2", "Open Shortcuts → Automation → +"),
        ("3", "Choose App → select Nowhere → pick \"Is Closed\""),
        ("4", "Set the action to the wallpaper shortcut"),
        ("5", "Turn off \"Ask Before Running\""),
    ]

    var body: some View {
        ZStack {
            SettingsGradientBG(model: model)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    DetailHeader(title: String(localized: "Wallpaper", comment: "Settings section title"))
                        .padding(.horizontal, 16)

                    // MARK: - Description
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles")
                                .font(.title3)
                                .foregroundStyle(AppColors.brandAccent)
                            Text(String(localized: "Auto-wallpaper"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(theme.adaptivePrimaryText)
                        }

                        Text(String(localized: "Set today's energy canvas as your Lock Screen wallpaper automatically each time you close the app."))
                            .font(.subheadline)
                            .foregroundColor(theme.adaptiveSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .glassCard()
                    .padding(.horizontal, 16)

                    // MARK: - Steps
                    VStack(alignment: .leading, spacing: 0) {
                        SettingsSectionLabel(text: String(localized: "SETUP", comment: "Wallpaper section header"))
                            .padding(.horizontal, 14)
                            .padding(.top, 14)
                            .padding(.bottom, 10)

                        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                            if index > 0 {
                                DetailDivider()
                            }
                            HStack(alignment: .top, spacing: 12) {
                                Text(step.number)
                                    .font(.caption.weight(.bold).monospacedDigit())
                                    .foregroundStyle(AppColors.brandAccent)
                                    .frame(width: 20, height: 20)
                                    .background(Circle().fill(AppColors.brandAccent.opacity(0.15)))

                                Text(step.text)
                                    .font(.subheadline)
                                    .foregroundColor(theme.adaptiveSecondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                    }
                    .glassCard()
                    .padding(.horizontal, 16)

                    // MARK: - CTA
                    Button {
                        openURL(shortcutURL)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.subheadline.weight(.semibold))
                            Text(String(localized: "Get Wallpaper Shortcut"))
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(AppColors.brandAccent))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 80)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: topCardHeight)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
