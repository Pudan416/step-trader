import SwiftUI

struct SettingsHelpPage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            SettingsDetailBackground(model: model)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    SettingsLabeledGroup(title: String(localized: "Get things working")) {
                        NavigationLink { SettingsPermissionsPage(model: model) } label: {
                            SettingsNavRow(icon: "heart", title: String(localized: "Health data & permissions"))
                        }
                        DetailDivider()
                        NavigationLink { SettingsWidgetPage(model: model) } label: {
                            SettingsNavRow(icon: "square.stack.3d.up", title: String(localized: "Add a widget"))
                        }
                        DetailDivider()
                        NavigationLink { SettingsShortcutPage(model: model) } label: {
                            SettingsNavRow(icon: "photo", title: String(localized: "Set up wallpaper"))
                        }
                    }
                    SettingsLabeledGroup(title: String(localized: "About your canvas")) {
                        NavigationLink { ManualsPage(model: model) } label: {
                            SettingsNavRow(icon: "book", title: String(localized: "How Nowhere works"))
                        }
                    }
                    SettingsLabeledGroup(title: String(localized: "Get in touch")) {
                        NavigationLink { SettingsAboutPage(model: model) } label: {
                            SettingsNavRow(icon: "bubble.left", title: String(localized: "Contact & feedback"))
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(16)
            }
        }
        .settingsDetailPage(title: String(localized: "Help & feedback"))
    }
}
