import SwiftUI

struct SettingsAboutPage: View {
    @ObservedObject var model: AppModel
    @Environment(\.openURL) private var openURL
    @Environment(\.appTheme) private var theme

    private enum Identity {
        static let brandName = "Nowhere"
        static let developerName = "Konstantin Pudan"
        static let feedbackEmail = "hello@itsnowhere.net"
        static let telegramHandle = "@pudan416"
        static let telegramURL = "https://t.me/pudan416"
        static let websiteURL = "https://nowhere.pudan.me"
        static let websiteDisplay = "nowhere.pudan.me"
        static let productHuntURL = "https://www.producthunt.com/products/nowhere-now-here"
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
            SettingsDetailBackground(model: model)

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    // MARK: - Brand Identity
                    SettingsGroupedSurface {
                        VStack(spacing: 12) {
                            Text(Identity.brandName)
                                .font(.unbounded(28, weight: .semibold, relativeTo: .title2))
                                .fontDesign(nil)
                                .foregroundStyle(SettingsCardAppearance.primaryText)

                            Text(String(localized: "You are not nowhere. You are now here.", comment: "App philosophy tagline"))
                                .font(.geist(.subheadline))
                                .foregroundStyle(theme.adaptiveSecondaryText)
                                .multilineTextAlignment(.center)

                            Text("v\(appVersion) (\(buildNumber))")
                                .font(.geist(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(theme.adaptiveMutedText)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .padding(.horizontal, 16)

                    // MARK: - Info
                    SettingsGroupedSurface {
                        DetailInfoRow(
                            label: String(localized: "Developer"),
                            value: Identity.developerName
                        )
                    }
                    .padding(.horizontal, 16)

                    // MARK: - Contact
                    SettingsLabeledGroup(
                        title: String(localized: "Contact", comment: "About section header")
                    ) {
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

                        DetailDivider()

                        Button {
                            if let url = URL(string: Identity.productHuntURL) {
                                openURL(url)
                            }
                        } label: {
                            SettingsLinkRow(
                                icon: "arrow.up.right.square",
                                title: "Product Hunt",
                                detail: "Nowhere (Now Here)"
                            )
                        }
                        .buttonStyle(MattePressStyle())
                    }
                    .padding(.horizontal, 16)

                    NavigationLink {
                        FontLicensesPage(model: model)
                    } label: {
                        SettingsLinkRow(
                            icon: "textformat",
                            title: String(localized: "Font licenses"),
                            detail: "Onest · Nowhere Display"
                        )
                    }
                    .buttonStyle(MattePressStyle())
                    .settingsCardSurface()
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 80)
            }
        }
        .overlay { }
        .settingsDetailPage(title: String(localized: "About", comment: "Settings section title"))
    }
}

private struct FontLicensesPage: View {
    @ObservedObject var model: AppModel
    @Environment(\.appTheme) private var theme

    private let fonts = [
        (name: "Onest", resource: "Onest-OFL"),
        (name: "Nowhere Display", resource: "NowhereDisplay-OFL"),
    ]

    var body: some View {
        ZStack {
            SettingsDetailBackground(model: model)
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    ForEach(fonts, id: \.resource) { font in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(font.name)
                                .font(.onest(.headline))
                            Text(license(named: font.resource))
                                .font(.onest(.footnote))
                                .textSelection(.enabled)
                        }
                    }
                }
                .foregroundStyle(theme.adaptivePrimaryText)
                .padding(.horizontal, 16)
                .padding(.bottom, 80)
            }
        }
        .settingsDetailPage(title: String(localized: "Font licenses"))
    }

    private func license(named name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return String(localized: "License unavailable")
        }
        return text
    }
}

#Preview {
    NavigationStack {
        SettingsAboutPage(model: DIContainer.shared.makeAppModel())
    }
}
