import SwiftUI

struct SettingsAboutPage: View {
    @ObservedObject var model: AppModel
    @Environment(\.topCardHeight) private var topCardHeight
    @Environment(\.openURL) private var openURL
    @Environment(\.appTheme) private var theme

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
                VStack(alignment: .leading, spacing: 16) {
                    DetailHeader(title: String(localized: "About", comment: "Settings section title"))
                        .padding(.horizontal, 16)

                    // MARK: - Brand Identity
                    VStack(spacing: 12) {
                        Text("Nowhere")
                            .font(.system(size: 28, weight: .black, design: .serif))
                            .foregroundStyle(theme.adaptivePrimaryText)

                        Text(String(localized: "You are not nowhere. You are now here.", comment: "App philosophy tagline"))
                            .font(.subheadline)
                            .foregroundStyle(theme.adaptiveSecondaryText)
                            .multilineTextAlignment(.center)

                        Text("v\(appVersion) (\(buildNumber))")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(theme.adaptiveMutedText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .glassCard()
                    .padding(.horizontal, 16)

                    // MARK: - Info
                    VStack(spacing: 0) {
                        DetailInfoRow(
                            label: String(localized: "Developer"),
                            value: "Konstantin Pudan"
                        )
                        DetailDivider()
                        DetailInfoRow(
                            label: String(localized: "Version"),
                            value: appVersion
                        )
                    }
                    .glassCard()
                    .padding(.horizontal, 16)

                    // MARK: - Contact
                    VStack(alignment: .leading, spacing: 0) {
                        SettingsSectionLabel(text: String(localized: "CONTACT", comment: "About section header"))
                            .padding(.horizontal, 14)
                            .padding(.top, 14)
                            .padding(.bottom, 6)

                        Button {
                            if let url = URL(string: "mailto:hello@itsnowhere.net") {
                                openURL(url)
                            }
                        } label: {
                            SettingsLinkRow(
                                icon: "envelope",
                                title: String(localized: "Feedback"),
                                detail: "hello@itsnowhere.net"
                            )
                        }
                        .buttonStyle(.plain)

                        DetailDivider()

                        Button {
                            if let url = URL(string: "https://t.me/pudan") {
                                openURL(url)
                            }
                        } label: {
                            SettingsLinkRow(
                                icon: "paperplane",
                                title: String(localized: "Telegram"),
                                detail: "@pudan416"
                            )
                        }
                        .buttonStyle(.plain)

                        DetailDivider()

                        Button {
                            if let url = URL(string: "https://itsnowhere.net") {
                                openURL(url)
                            }
                        } label: {
                            SettingsLinkRow(
                                icon: "globe",
                                title: String(localized: "Website"),
                                detail: "itsnowhere.net"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .glassCard()
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
