import SwiftUI

struct SettingsAboutPage: View {
    @ObservedObject var model: AppModel
    @Environment(\.topCardHeight) private var topCardHeight
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @Environment(\.appTheme) private var theme

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        ZStack {
            SettingsGradientBG(model: model)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    DetailHeader(title: String(localized: "About", comment: "Settings section title"))

                    VStack(alignment: .leading, spacing: 0) {
                    DetailInfoRow(label: String(localized: "Developer"), value: "Konstantin Pudan")
                    DetailDivider()
                    DetailInfoRow(label: String(localized: "Version"), value: appVersion)
                    DetailDivider()
                    Button {
                        if let url = URL(string: "mailto:hello@itsnowhere.net") {
                            openURL(url)
                        }
                    } label: {
                        HStack {
                            Text(String(localized: "Feedback"))
                                .font(.subheadline)
                                .foregroundColor(theme.adaptivePrimaryText)
                            Spacer()
                            Text("hello@itsnowhere.net")
                                .font(.caption)
                                .foregroundColor(theme.adaptiveSecondaryText)
                            Image(systemName: "envelope")
                                .font(.caption2)
                                .foregroundColor(theme.adaptiveMutedText)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    DetailDivider()
                    Button {
                        if let url = URL(string: "https://t.me/pudan") {
                            openURL(url)
                        }
                    } label: {
                        HStack {
                            Text(String(localized: "Telegram"))
                                .font(.subheadline)
                                .foregroundColor(theme.adaptivePrimaryText)
                            Spacer()
                            Text("@pudan416")
                                .font(.caption)
                                .foregroundColor(theme.adaptiveSecondaryText)
                            Image(systemName: "paperplane")
                                .font(.caption2)
                                .foregroundColor(theme.adaptiveMutedText)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    }
                .glassCard()

                    Text(String(localized: "You are not nowhere. You are now here.", comment: "App philosophy tagline"))
                        .font(.caption)
                        .foregroundStyle(theme.adaptiveMutedText)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)

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
