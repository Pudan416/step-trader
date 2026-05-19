import SwiftUI

struct SettingsAboutPage: View {
    @ObservedObject var model: AppModel
    @Environment(\.topCardHeight) private var topCardHeight
    @Environment(\.openURL) private var openURL
    @Environment(\.appTheme) private var theme

    private enum Identity {
        static let brandName = "Nowhere"
        static let developerName = "Konstantin Pudan"
        static let feedbackEmail = "hello@itsnowhere.net"
        static let telegramHandle = "@pudan416"
        static let telegramURL = "https://t.me/pudan416"
        static let websiteURL = "https://itsnowhere.net"
        static let websiteDisplay = "itsnowhere.net"
        static var feedbackMailto: String { "mailto:\(feedbackEmail)" }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        ZStack {
            SettingsGradientBG(model: model)

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    DetailHeader(title: String(localized: "About", comment: "Settings section title"))
                        .padding(.horizontal, 16)

                    // MARK: - Brand Identity
                    VStack(spacing: 12) {
                        Text(Identity.brandName)
                            .font(.system(size: 28, weight: .black, design: .serif))
                            .foregroundStyle(theme.adaptivePrimaryText)

                        Text(String(localized: "You are not nowhere. You are now here.", comment: "App philosophy tagline"))
                            .font(.subheadline)
                            .foregroundStyle(theme.adaptiveSecondaryText)
                            .multilineTextAlignment(.center)

                        Text("v\(appVersion) (\(buildNumber))")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(theme.adaptiveMutedText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)

                    DetailDivider().padding(.horizontal, 16)

                    // MARK: - Info
                    VStack(spacing: 0) {
                        DetailInfoRow(
                            label: String(localized: "Developer"),
                            value: Identity.developerName
                        )
                        DetailDivider()
                        DetailInfoRow(
                            label: String(localized: "Version"),
                            value: appVersion
                        )
                    }
                    .padding(.horizontal, 16)

                    DetailDivider().padding(.horizontal, 16)

                    // MARK: - Contact
                    VStack(alignment: .leading, spacing: 0) {
                        SettingsSectionLabel(text: String(localized: "Contact", comment: "About section header"))
                            .padding(.horizontal, 14)
                            .padding(.bottom, 8)

                        Button {
                            if let url = URL(string: Identity.feedbackMailto) {
                                openURL(url)
                            }
                        } label: {
                            SettingsLinkRow(
                                icon: "envelope",
                                title: String(localized: "Feedback"),
                                detail: Identity.feedbackEmail
                            )
                        }
                        .buttonStyle(MattePressStyle())

                        DetailDivider()

                        Button {
                            if let url = URL(string: Identity.telegramURL) {
                                openURL(url)
                            }
                        } label: {
                            SettingsLinkRow(
                                icon: "paperplane",
                                title: String(localized: "Telegram"),
                                detail: Identity.telegramHandle
                            )
                        }
                        .buttonStyle(MattePressStyle())

                        DetailDivider()

                        Button {
                            if let url = URL(string: Identity.websiteURL) {
                                openURL(url)
                            }
                        } label: {
                            SettingsLinkRow(
                                icon: "globe",
                                title: String(localized: "Website"),
                                detail: Identity.websiteDisplay
                            )
                        }
                        .buttonStyle(MattePressStyle())
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 80)
            }
        }
        .overlay { }
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: topCardHeight)
        }
        .toolbar(.hidden, for: .navigationBar)
        .detailSwipeBack()
    }
}

#Preview {
    NavigationStack {
        SettingsAboutPage(model: DIContainer.shared.makeAppModel())
    }
}
