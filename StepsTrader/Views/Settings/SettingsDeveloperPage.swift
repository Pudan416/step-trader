#if DEBUG
import SwiftUI
#if canImport(DeviceActivity)
import DeviceActivity
#endif

struct SettingsDeveloperPage: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var authService = AuthenticationService.shared
    @Environment(\.appTheme) private var theme
    @Environment(CoachMarkManager.self) private var coachMarkManager

    @State private var diagCopied = false
    @State private var budgetsReset = false
    @State private var colorsRestored = false
    @State private var healthReset = false
    @State private var showOnboardingDemo = false
    @State private var replayOnboardingLive = false
    @State private var debugFeatureTip: FeatureTip?
    @State private var featureTipsReset = false
    @State private var shieldActionLogs: [String] = []
    @State private var showShieldActionLogs = false

    var body: some View {
        ZStack {
            SettingsDetailBackground(model: model)

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    SettingsGroupedSurface {
                        shieldDiagnosticsRows
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 80)
            }
        }
        .settingsDetailPage(title: String(localized: "Developer", comment: "Settings developer page title"))
        .fullScreenCover(isPresented: $showOnboardingDemo) {
            OnboardingDemoView()
        }
        .fullScreenCover(isPresented: $replayOnboardingLive) {
            OnboardingFlowView(
                model: model,
                authService: authService,
                showsDebugSkip: true
            ) {
                replayOnboardingLive = false
            }
        }
    }

    @ViewBuilder
    private var shieldDiagnosticsRows: some View {
        Button {
            let text = model.blockingStore.dumpShieldDiagnostics()
            UIPasteboard.general.string = text
            diagCopied = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                diagCopied = false
            }
        } label: {
            diagButton(
                icon: "shield.lefthalf.filled",
                text: diagCopied
                    ? String(localized: "Copied to clipboard!", comment: "Developer diagnostic success")
                    : String(localized: "Copy Shield Diagnostics", comment: "Developer diagnostic action"),
                highlight: diagCopied,
                trailing: "doc.on.clipboard"
            )
        }
        .buttonStyle(MattePressStyle())

        rowDivider

        Button {
            let defaults = UserDefaults(suiteName: SharedKeys.appGroupId)
            shieldActionLogs = defaults?.stringArray(forKey: SharedKeys.shieldActionLogs) ?? [
                String(localized: "(no logs yet)", comment: "Empty ShieldAction logs placeholder")
            ]
            showShieldActionLogs = true
        } label: {
            diagButton(
                icon: "bell.badge",
                text: String(localized: "View ShieldAction Logs", comment: "Developer diagnostic action"),
                trailing: "list.bullet.rectangle"
            )
        }
        .buttonStyle(MattePressStyle())
        .sheet(isPresented: $showShieldActionLogs) {
            NavigationStack {
                List(shieldActionLogs, id: \.self) { log in
                    Text(log).font(.geist(.caption2)).textSelection(.enabled)
                }
                .navigationTitle(String(localized: "ShieldAction Logs"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(String(localized: "Copy All")) {
                            UIPasteboard.general.string = shieldActionLogs.joined(separator: "\n")
                        }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button(String(localized: "Clear")) {
                            UserDefaults(suiteName: SharedKeys.appGroupId)?.removeObject(forKey: SharedKeys.shieldActionLogs)
                            shieldActionLogs = [
                                String(localized: "(cleared)", comment: "Cleared ShieldAction logs placeholder")
                            ]
                        }
                    }
                }
            }
        }

        rowDivider

        Button {
            let defaults = UserDefaults.stepsTrader()
            for group in model.blockingStore.ticketGroups {
                defaults.removeObject(forKey: SharedKeys.usageBudgetKey(group.id))
                defaults.removeObject(forKey: SharedKeys.usageBudgetStartedKey(group.id))
                defaults.removeObject(forKey: SharedKeys.usageBudgetInitialKey(group.id))
                defaults.removeObject(forKey: SharedKeys.usageBudgetExpiryKey(group.id))
            }
            #if canImport(DeviceActivity)
            let center = DeviceActivityCenter()
            let budgetActivities = center.activities.filter { $0.rawValue.hasPrefix("usageBudget_") }
            center.stopMonitoring(budgetActivities)
            #endif
            model.rebuildFamilyControlsShield()
            budgetsReset = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                budgetsReset = false
            }
        } label: {
            diagButton(
                icon: "clock.arrow.circlepath",
                text: budgetsReset
                    ? String(localized: "All budgets cleared!", comment: "Developer diagnostic success")
                    : String(localized: "Reset All Usage Budgets", comment: "Developer diagnostic action"),
                highlight: budgetsReset,
                trailing: "trash"
            )
        }
        .buttonStyle(MattePressStyle())

        rowDivider

        Button {
            model.spentStepsToday = 0
            model.persistDailyEnergyState()
            model.recalculateDailyEnergy()
            colorsRestored = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                colorsRestored = false
            }
        } label: {
            diagButton(
                icon: "paintpalette",
                text: colorsRestored
                    ? String(localized: "Colors restored!", comment: "Developer diagnostic success")
                    : String(localized: "Restore Colors to Max", comment: "Developer diagnostic action"),
                highlight: colorsRestored,
                trailing: "arrow.counterclockwise"
            )
        }
        .buttonStyle(MattePressStyle())

        rowDivider

        Button {
            Task {
                await model.debugForceHealthReset()
                healthReset = true
                try? await Task.sleep(for: .seconds(2))
                healthReset = false
            }
        } label: {
            diagButton(
                icon: "heart.text.clipboard",
                text: healthReset
                    ? String(localized: "Health data refreshed!", comment: "Developer diagnostic success")
                    : String(localized: "Force Health Reset (New Day)", comment: "Developer diagnostic action"),
                highlight: healthReset,
                trailing: "arrow.clockwise"
            )
        }
        .buttonStyle(MattePressStyle())

        rowDivider

        Button {
            showOnboardingDemo = true
        } label: {
            diagButton(
                icon: "play.rectangle",
                text: String(localized: "Preview Onboarding (Demo)", comment: "Developer diagnostic action"),
                trailing: "eye"
            )
        }
        .buttonStyle(MattePressStyle())

        rowDivider

        Button {
            replayOnboardingLive = true
        } label: {
            diagButton(
                icon: "arrow.counterclockwise.circle",
                text: String(localized: "Replay Onboarding (Live)", comment: "Developer diagnostic action"),
                trailing: "restart"
            )
        }
        .buttonStyle(MattePressStyle())

        rowDivider

        Button {
            coachMarkManager.start()
        } label: {
            diagButton(
                icon: "hand.point.up.left",
                text: String(localized: "Preview Coach Marks", comment: "Developer diagnostic action"),
                trailing: "questionmark.circle"
            )
        }
        .buttonStyle(MattePressStyle())

        rowDivider

        Button {
            debugFeatureTip = .widgets
        } label: {
            diagButton(
                icon: "square.stack.3d.up",
                text: String(localized: "Preview Widget Tip", comment: "Developer diagnostic action"),
                trailing: "eye"
            )
        }
        .buttonStyle(MattePressStyle())

        rowDivider

        Button {
            debugFeatureTip = .wallpaper
        } label: {
            diagButton(
                icon: "photo.on.rectangle.angled",
                text: String(localized: "Preview Wallpaper Tip", comment: "Developer diagnostic action"),
                trailing: "eye"
            )
        }
        .buttonStyle(MattePressStyle())

        rowDivider

        Button {
            FeatureTip.resetAllSeenFlags()
            featureTipsReset = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                featureTipsReset = false
            }
        } label: {
            diagButton(
                icon: "arrow.counterclockwise",
                text: featureTipsReset
                    ? String(localized: "Feature tip flags cleared!", comment: "Developer diagnostic success")
                    : String(localized: "Reset Feature Tip Flags", comment: "Developer diagnostic action"),
                highlight: featureTipsReset,
                trailing: "trash"
            )
        }
        .buttonStyle(MattePressStyle())
        .sheet(item: $debugFeatureTip) { tip in
            FeatureTipSheet(tip: tip)
        }
    }

    private func diagButton(
        icon: String,
        text: String,
        highlight: Bool = false,
        trailing: String? = nil
    ) -> some View {
        HStack(spacing: 12) {
            rowIcon(icon)
            Text(text)
                .font(.geist(.subheadline))
                .foregroundStyle(highlight ? .green : theme.adaptivePrimaryText)
            Spacer()
            if let trailing {
                Image(systemName: trailing)
                    .font(.geist(.caption2))
                    .foregroundStyle(theme.adaptiveMutedText.opacity(0.7))
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func rowIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.geist(size: 15))
            .foregroundStyle(theme.adaptiveSecondaryText)
            .frame(width: 24)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(theme.adaptiveDividerColor.opacity(0.5))
            .frame(height: 0.5)
            .padding(.leading, 36)
    }
}
#endif
