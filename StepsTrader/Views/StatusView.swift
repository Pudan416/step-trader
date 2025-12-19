import AudioToolbox
import SwiftUI
import UserNotifications

// MARK: - StatusView
struct StatusView: View {
    @ObservedObject var model: AppModel
    @State private var timer: Timer?
    @State private var lastAvailableMinutes: Int = 0
    @State private var lastNotificationMinutes: Int = -1

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Полоса с остатком шагов сверху
                    remainingStepsBarView

                    // Мини-статистика (как просили: Шаги, Всего минут, Потрачено)
                    miniStatsView

                    // Большой дисплей оставшихся открытий по центру
                    bigOpensDisplayView

                    Spacer(minLength: 20)
                }
                .padding()
            }
        }
        .onAppear {
            onAppear()
        }
        .onDisappear {
            onDisappear()
        }
        .onChange(of: model.isTrackingTime) { _, isTracking in
            if isTracking {
                startTimer()
            } else {
                stopTimer()
            }
        }
    }

    // MARK: - Remaining Steps Bar
    private var remainingStepsBarView: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Step balance")
                    .font(.headline)
                Spacer()
                Text("\(remainingStepsToday)")
                    .font(.headline)
                    .foregroundColor(.blue)
            }

            ProgressView(
                value: Double(remainingStepsToday), total: max(1.0, Double(Int(model.stepsToday)))
            )
            .progressViewStyle(LinearProgressViewStyle(tint: .blue))
            .scaleEffect(x: 1, y: 2, anchor: .center)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
    }

    // MARK: - Mini Stats (Шаги сегодня, Потрачено шагов, Тариф)
    private var miniStatsView: some View {
        HStack(spacing: 16) {
            StatMiniCard(
                icon: "figure.walk",
                title: "Steps today",
                value: "\(Int(model.stepsToday))",
                color: .blue
            )

            StatMiniCard(
                icon: "shoeprints.fill",
                title: "Steps spent",
                value: "\(model.spentStepsToday)",
                color: .green
            )

            StatMiniCard(
                icon: "creditcard",
                title: "Tariff",
                value: "\(model.budget.tariff.displayName)",
                color: .orange
            )
        }
    }

    // MARK: - Big Opens Display
    private var bigOpensDisplayView: some View {
        VStack(spacing: 12) {
            if model.isBlocked {
                VStack(spacing: 8) {
                    Text("⏰")
                        .font(.system(size: 60))

                    Text("Time expired!")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }
            } else {
                VStack(spacing: 8) {
                    Text("\(opensLeftToday)")
                        .font(.system(size: 80, weight: .bold, design: .rounded))
                        .foregroundColor(timeColor)
                        .contentTransition(.numericText())

                    Text("Opens left today: \(opensLeftToday)")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(timeBackgroundColor)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        )
    }

    // MARK: - Progress Bar
    private var progressBarView: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Time used")
                    .font(.headline)
                Spacer()
                Text("\(progressPercentage)%")
                    .font(.headline)
                    .foregroundColor(timeColor)
            }

            ProgressView(value: progressValue, total: 1.0)
                .progressViewStyle(LinearProgressViewStyle(tint: timeColor))
                .scaleEffect(x: 1, y: 2, anchor: .center)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
    }

    // MARK: - Computed Properties
    private var remainingStepsToday: Int {
        return max(0, Int(model.stepsToday) - model.spentStepsToday)
    }

    private var calculatedRemainingMinutes: Int {
        return max(0, model.dailyBudgetMinutes - model.spentMinutes)
    }

    // Количество оставшихся открытий сегодня по формуле: (stepsToday - spentStepsToday) / entryCostSteps
    private var opensLeftToday: Int {
        let totalSteps = Int(model.stepsToday)
        let spent = model.spentStepsToday
        let cost = max(1, model.entryCostSteps)
        let available = max(0, totalSteps - spent)
        return available / cost
    }

    private var timeColor: Color {
        if calculatedRemainingMinutes <= 0 {
            return .red
        } else if calculatedRemainingMinutes < 10 {
            return .red
        } else if calculatedRemainingMinutes <= 30 {
            return .orange
        } else {
            return .blue
        }
    }

    private var timeBackgroundColor: Color {
        if model.isBlocked {
            return .red.opacity(0.1)
        } else {
            return timeColor.opacity(0.1)
        }
    }

    private var progressValue: Double {
        guard model.dailyBudgetMinutes > 0 else { return 0 }
        let used = model.dailyBudgetMinutes - model.remainingMinutes
        return Double(used) / Double(model.dailyBudgetMinutes)
    }

    private var progressPercentage: Int {
        Int(progressValue * 100)
    }

    private func formatTime(minutes: Int) -> String { "\(minutes) min" }

    // MARK: - Timer Management
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            // Принудительно обновляем бюджет из хранилища
            Task { @MainActor in
                model.reloadBudgetFromStorage()
            }

            // Принудительно обновляем потраченное время
            Task { @MainActor in
                model.loadSpentTime()
            }

            // Обновляем последнее доступное время
            if calculatedRemainingMinutes > 0 {
                lastAvailableMinutes = calculatedRemainingMinutes
            }

            // Отправляем уведомление с оставшимся временем
            sendRemainingTimeNotificationIfNeeded()

            // Проверяем, не истекло ли время
            checkTimeExpiration()
        }
    }

    private func checkTimeExpiration() {
        // Проверяем, не истекло ли время и активно ли отслеживание
        if model.isTrackingTime && calculatedRemainingMinutes <= 0 && !model.isBlocked {
            print("⏰ Time expired in StatusView - triggering blocking")

            // Сохраняем последнее доступное время для уведомления
            let minutesBeforeBlocking = lastAvailableMinutes > 0 ? lastAvailableMinutes : 0

            // Останавливаем отслеживание
            model.stopTracking()

            // Устанавливаем блокировку
            model.isBlocked = true
            model.message = "⏰ Time is up!"

            // Применяем реальную блокировку приложений
            if let familyService = model.familyControlsService as? FamilyControlsService {
                familyService.enableShield()
                print("🛡️ Applied real app blocking via ManagedSettings")
            }

            // Отправляем уведомления с количеством минут, которое было доступно
            model.notificationService.sendTimeExpiredNotification(
                remainingMinutes: minutesBeforeBlocking)
            model.sendReturnToAppNotification()
            AudioServicesPlaySystemSound(1005)
        }

        // Проверяем, не появилось ли новое время после блокировки
        if model.isBlocked && calculatedRemainingMinutes > 0 {
            print("🔄 New time available after blocking - unblocking app")
            unblockApp()
        }
    }

    private func unblockApp() {
        // Снимаем блокировку
        model.isBlocked = false
        model.message = "✅ Time restored! Available: \(calculatedRemainingMinutes) min"

        // Снимаем реальную блокировку приложений
        if let familyService = model.familyControlsService as? FamilyControlsService {
            familyService.disableShield()
            print("🔓 Removed app blocking via ManagedSettings")
        }

        // Отправляем уведомление о разблокировке
        model.notificationService.sendUnblockNotification(
            remainingMinutes: calculatedRemainingMinutes)
        AudioServicesPlaySystemSound(1003)  // Success sound
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func sendRemainingTimeNotificationIfNeeded() {
        // Отправляем уведомление только если время меньше 10 минут и больше 0
        // И только если минуты изменились (чтобы не спамить)
        if calculatedRemainingMinutes > 0 && calculatedRemainingMinutes < 10
            && calculatedRemainingMinutes != lastNotificationMinutes
        {
            model.notificationService.sendRemainingTimeNotification(
                remainingMinutes: calculatedRemainingMinutes)
            lastNotificationMinutes = calculatedRemainingMinutes
        }
    }

    private func onAppear() {
        if model.isTrackingTime {
            startTimer()
        }
    }

    private func onDisappear() {
        stopTimer()
    }

    private func openInstagram() {
        // Устанавливаем флаг, что Instagram открывается через наше приложение
        let userDefaults = UserDefaults.stepsTrader()
        userDefaults.set(Date(), forKey: "instagramOpenedFromStepsTrader")

        // Открываем Instagram через основной URL scheme
        if let url = URL(string: "instagram://app") {
            UIApplication.shared.open(url) { success in
                if !success {
                    // Если не удалось открыть Instagram, открываем App Store
                    if let appStoreURL = URL(
                        string: "https://apps.apple.com/app/instagram/id389801252")
                    {
                        UIApplication.shared.open(appStoreURL)
                    }
                } else {
                    // Instagram открылся успешно, НЕ минимизируем приложение
                    // Пусть пользователь сам переключится на Instagram
                    print("✅ Instagram opened successfully")
                }
            }
        }
    }
}
