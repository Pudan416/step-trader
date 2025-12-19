import SwiftUI

// MARK: - SettingsView
struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationView {
            Form {
                // Баланс и стоимость входа
                balanceSection

                // Стоимость входа (тариф)
                tariffSection

                // Статус системы и управление
                systemStatusSection
                managementSection
            }
        }
    }

    // MARK: - Computed Properties
    private var remainingStepsToday: Int {
        // Остаток шагов = шаги из HealthKit - шаги потраченные на входы
        return max(0, Int(model.stepsToday) - model.spentStepsToday)
    }

    private func isTariffAvailable(_ tariff: Tariff) -> Bool {
        let requiredSteps = Int(tariff.stepsPerMinute)
        // Проверяем доступность на основе оставшихся шагов, а не потраченных минут
        return Int(model.stepsToday) >= requiredSteps
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
                    HStack {
                        Text("Entry cost")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(model.entryCostSteps)")
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
                Text("Choose the entry cost and step-to-minute rate")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ForEach(Tariff.allCases, id: \.self) { tariff in
                    TariffOptionView(
                        tariff: tariff,
                        isSelected: model.budget.tariff == tariff,
                        isDisabled: !isTariffAvailable(tariff),
                        stepsToday: model.stepsToday
                    ) {
                        selectTariff(tariff)
                        model.persistEntryCost(tariff: tariff)
                    }
                    .overlay(alignment: .trailing) {
                        Text("Entry: \(tariff.entryCostSteps) steps")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.trailing, 8)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Management Section
    private var managementSection: some View {
        Section("Management") {
            VStack(spacing: 12) {
                Button("📲 Install PayGate Shortcut") {
                    model.installPayGateShortcut()
                }
                .frame(maxWidth: .infinity)

                Button("🔍 Diagnostics") {
                    model.runDiagnostics()
                }
                .frame(maxWidth: .infinity)

                Button("🧪 Test handoff") {
                    testHandoffToken()
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.bordered)
                .foregroundColor(.blue)
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - System Status Section
    private var systemStatusSection: some View {
        Section("System status") {
            VStack(alignment: .leading, spacing: 12) {
                StatusRow(
                    icon: "heart.fill",
                    title: "HealthKit",
                    status: .connected,
                    description: "Access to step data"
                )

                StatusRow(
                    icon: "bell.fill",
                    title: "Notifications",
                    status: .connected,
                    description: "Push notifications enabled"
                )
            }
            .padding(.vertical, 8)
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
