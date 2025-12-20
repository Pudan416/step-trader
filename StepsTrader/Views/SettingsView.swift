import SwiftUI

// MARK: - SettingsView
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var guideApp: GuideItem?
    @State private var showOtherInfo: Bool = false

    var body: some View {
        NavigationView {
            Form {
                // Баланс и стоимость входа
                balanceSection

                // Стоимость входа (тариф)
                tariffSection

                // Выбор приложений для автоматизации
                automationAppsSection
            }
        }
        .sheet(item: $guideApp, onDismiss: { guideApp = nil }) { item in
            AutomationGuideView(app: item)
        }
    }

    // MARK: - Computed Properties
    private var remainingStepsToday: Int {
        // Остаток шагов = шаги из HealthKit - шаги потраченные на входы
        return max(0, Int(model.stepsToday) - model.spentStepsToday)
    }

    // MARK: - Balance Section (пер-входовая модель)
    private var balanceSection: some View {
        Section("Step balance") {
            VStack(spacing: 14) {
                // Шкала остатка шагов
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Remaining: \(remainingStepsToday) of \(Int(model.stepsToday))")
                            .font(.headline)
                        Spacer()
                    }
                    ProgressView(
                        value: Double(remainingStepsToday),
                        total: max(1.0, Double(Int(model.stepsToday)))
                    )
                    .tint(remainingStepsToday <= 0 ? .red : .blue)
                }

                // Мини-статы под шкалой
                VStack(spacing: 8) {
                    HStack {
                        Text("Steps today")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(model.stepsToday))")
                            .foregroundColor(.primary)
                    }
                    HStack {
                        Text("Steps spent")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(model.spentStepsToday)")
                            .foregroundColor(.primary)
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: - Tariff Section
    private var tariffSection: some View {
        Section("Step-to-time tariff") {
            VStack(alignment: .leading, spacing: 16) {
                Text("Choose entry cost / steps per minute")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("You can switch anytime; opening apps still checks your step balance.")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Slider(
                    value: tariffSliderBinding,
                    in: 0...Double(tariffOptions.count - 1),
                    step: 1
                )

                HStack {
                    ForEach(Array(tariffOptions.enumerated()), id: \.offset) { idx, tariff in
                        VStack(spacing: 4) {
                            Text(tariff.displayName)
                                .font(.caption2)
                                .fontWeight(model.budget.tariff == tariff ? .bold : .regular)
                            Text("\(tariff.entryCostSteps) steps")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .opacity(idx == currentTariffIndex ? 1 : 0.6)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Automation Apps Section
    private var automationAppsSection: some View {
        let apps: [(name: String, scheme: String, icon: String, link: String, bundleId: String)] = [
            ("YouTube", "youtube://", "▶️", "https://www.icloud.com/shortcuts/f880905ebcb244e2a4dcc43aee73a9fd", "com.google.ios.youtube"),
            ("Instagram", "instagram://", "📱", "https://www.icloud.com/shortcuts/34ba0e1e5a2a441f9a2a2d31358a92a4", "com.burbn.instagram"),
            ("TikTok", "tiktok://", "🎵", "https://www.icloud.com/shortcuts/6f2b49ec00ec4660b633b807decaa753", "com.zhiliaoapp.musically"),
        ]
        let configured = automationConfiguredSet
        let pending = automationPendingSet

        return Section("Automation apps") {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    automationButton(apps[0], status: statusFor(apps[0], configured: configured, pending: pending))
                    automationButton(apps[1], status: statusFor(apps[1], configured: configured, pending: pending))
                }
                HStack(spacing: 12) {
                    automationButton(apps[2], status: statusFor(apps[2], configured: configured, pending: pending))
                    Button {
                        guard guideApp == nil else { return }
                        showOtherInfo = true
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.1))
                                .frame(height: 70)
                            VStack(spacing: 6) {
                                Text("✨")
                                    .font(.title2)
                                Text("Other app")
                                    .font(.subheadline)
                            }
                            .foregroundColor(.secondary)
                        }
                    }
                    .alert("More apps coming soon", isPresented: $showOtherInfo) {
                        Button("OK", role: .cancel) {}
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }

    private var selectedAppScheme: String? {
        UserDefaults.stepsTrader().string(forKey: "selectedAppScheme")
    }
    
    private var automationConfiguredSet: Set<String> {
        let defaults = UserDefaults.stepsTrader()
        let configured = defaults.array(forKey: "automationConfiguredBundles") as? [String] ?? []
        let single = defaults.string(forKey: "automationBundleId")
        return Set(configured + (single.map { [$0] } ?? []))
    }

    private var tariffOptions: [Tariff] { Tariff.allCases }
    private var currentTariffIndex: Int { tariffOptions.firstIndex(of: model.budget.tariff) ?? 0 }
    private var tariffSliderBinding: Binding<Double> {
        Binding<Double>(
            get: { Double(currentTariffIndex) },
            set: { newValue in
                let clamped = min(max(Int(newValue.rounded()), 0), tariffOptions.count - 1)
                let tariff = tariffOptions[clamped]
                selectTariff(tariff)
                model.persistEntryCost(tariff: tariff)
            }
        )
    }

    private var automationPendingSet: Set<String> {
        let pending = UserDefaults.stepsTrader().array(forKey: "automationPendingBundles") as? [String] ?? []
        return Set(pending)
    }

    private enum AutomationStatus {
        case none
        case pending
        case configured
    }

    private struct GuideItem: Identifiable {
        var id: String { scheme }
        let name: String
        let icon: String
        let scheme: String
        let link: String
        let status: AutomationStatus
    }

    // MARK: - Guide Sheet
    private func automationButton(_ app: (name: String, scheme: String, icon: String, link: String, bundleId: String), status: AutomationStatus) -> some View {
        Button {
            guard !showOtherInfo, guideApp == nil else { return }
            UserDefaults.stepsTrader().set(app.scheme, forKey: "selectedAppScheme")
            markPending(bundleId: app.bundleId)
            let item = GuideItem(name: app.name, icon: app.icon, scheme: app.scheme, link: app.link, status: status)
            DispatchQueue.main.async {
                guideApp = item
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(backgroundColor(for: status))
                    .frame(height: 70)
                HStack {
                    Text(app.icon)
                        .font(.title2)
                    Text(app.name)
                        .fontWeight(.semibold)
                    Spacer()
                    statusIcon(for: status)
                }
                .padding(.horizontal, 12)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Guide Sheet
    private struct AutomationGuideView: View {
        @Environment(\.dismiss) private var dismiss
        let app: GuideItem

        var body: some View {
            NavigationView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    content

                    if let url = URL(string: app.link) {
                        Link(destination: url) {
                            HStack {
                                Image(systemName: "link")
                                Text(app.status == .configured ? "Update the modul" : "Get the modul")
                                    .fontWeight(.semibold)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.blue.opacity(0.1)))
                        }
                    }

                    Spacer()
                }
                .padding()
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            dismiss()
                        }
                    }
                }
            }
        }

        private var header: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text(app.icon)
                        .font(.system(size: 36))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.name)
                            .font(.title2)
                            .fontWeight(.bold)
                        switch app.status {
                        case .configured:
                            Text("Modul for \(app.name) is working")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        case .pending:
                            Text("The modul is provided but not connected to \(app.name)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        case .none:
                            Text("The modul for \(app.name) is not taken")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                if app.status == .configured || app.status == .pending {
                    Image(systemName: "checkmark.seal.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 80)
                        .foregroundColor(app.status == .configured ? .green : .yellow)
                        .padding(.top, 8)
                }
            }
        }

        @ViewBuilder
        private var content: some View {
            switch app.status {
            case .configured:
                EmptyView()
            case .pending:
                VStack(alignment: .leading, spacing: 10) {
                    Text("Finish setup:")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("1) Open Shortcuts → Automation → + → \"App\".")
                    Text("2) Choose \(app.name), set \"Is Opened\" + \"Run Immediately\".")
                    Text("3) Select the imported shortcut for \(app.name).")
                    Text("4) Launch \(app.name) once to activate the automation.")
                }
                .font(.callout)
            case .none:
                VStack(alignment: .leading, spacing: 10) {
                    Text("How to set up:")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("1) Tap \"Open shortcut\" below and add it.")
                    Text("2) Open Shortcuts → Automation → + → \"App\".")
                    Text("3) Choose \(app.name), set \"Is Opened\" + \"Run Immediately\".")
                    Text("4) Select the imported shortcut for \(app.name).")
                    Text("5) Launch \(app.name) once to activate the automation.")
                }
                .font(.callout)
            }
        }
    }

    // MARK: - Helpers
    private func statusFor(_ app: (name: String, scheme: String, icon: String, link: String, bundleId: String),
                           configured: Set<String>,
                           pending: Set<String>) -> AutomationStatus {
        if configured.contains(app.bundleId) { return .configured }
        if pending.contains(app.bundleId) { return .pending }
        return .none
    }

    private func backgroundColor(for status: AutomationStatus) -> Color {
        switch status {
        case .configured: return Color.green.opacity(0.15)
        case .pending: return Color.yellow.opacity(0.15)
        case .none: return Color.gray.opacity(0.1)
        }
    }

    @ViewBuilder
    private func statusIcon(for status: AutomationStatus) -> some View {
        switch status {
        case .configured:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .pending:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.yellow)
        case .none:
            EmptyView()
        }
    }

    private func markPending(bundleId: String) {
        var pending = UserDefaults.stepsTrader().array(forKey: "automationPendingBundles") as? [String] ?? []
        if !pending.contains(bundleId) {
            pending.append(bundleId)
            UserDefaults.stepsTrader().set(pending, forKey: "automationPendingBundles")
        }
    }
    // MARK: - Actions
    private func selectTariff(_ tariff: Tariff) {
        // Только сохраняем выбор тарифа, не пересчитываем бюджет
                        model.budget.updateTariff(tariff)
                        // Sync entry cost with new tariff
                        model.persistEntryCost(tariff: tariff)
        model.message =
            "✅ Tariff selected: \(tariff.displayName). The budget will recalculate when tracking starts."
    }

    private func testHandoffToken() {
        print("🧪 Testing handoff token creation...")

        let testToken = HandoffToken(
            targetBundleId: "com.burbn.instagram",
            targetAppName: "Instagram",
            createdAt: Date(),
            tokenId: UUID().uuidString
        )

        let userDefaults = UserDefaults.stepsTrader()

        if let tokenData = try? JSONEncoder().encode(testToken) {
            userDefaults.set(tokenData, forKey: "handoffToken")
            print("🧪 Test token created and saved: \(testToken.tokenId)")
            model.message =
                "🧪 Test handoff token created! Relaunch the app to verify."
        } else {
            print("❌ Failed to create test token")
            model.message = "❌ Failed to create test token"
        }
    }
}
