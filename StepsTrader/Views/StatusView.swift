import SwiftUI
import AudioToolbox
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

                    // Мини-статистика (переработано под оплату за вход)
                    miniStatsView

                    // Карточка оплаты входа
                    VStack(spacing: 12) {
                        HStack {
                            Text("Баланс шагов")
                                .font(.headline)
                            Spacer()
                            Text("\(model.stepsBalance)")
                                .font(.headline)
                                .foregroundColor(model.stepsBalance < model.entryCostSteps ? .red : .green)
                        }
                        HStack {
                            Text("Стоимость входа")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(model.entryCostSteps)")
                                .foregroundColor(.primary)
                        }
                        Button("Оплатить вход") {
                            Task {
                                await model.refreshStepsBalance()
                                if model.canPayForEntry() { 
                                    _ = model.payForEntry()
                                    // Редирект в Instagram после оплаты
                                    openInstagram()
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.borderedProminent)
                        .disabled(model.stepsBalance < model.entryCostSteps)
                        
                        Button("📱 Открыть Instagram") {
                            openInstagram()
                        }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.bordered)
                        .foregroundColor(.pink)
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))

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
        .onChange(of: model.isTrackingTime) { isTracking in
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
                Text("Остаток шагов")
                    .font(.headline)
                Spacer()
                Text("\(remainingStepsToday)")
                    .font(.headline)
                    .foregroundColor(.blue)
            }
            
            ProgressView(value: Double(remainingStepsToday), total: Double(Int(model.stepsToday)))
                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                .scaleEffect(x: 1, y: 2, anchor: .center)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
    }
    
    // MARK: - Mini Stats (переработано)
    private var miniStatsView: some View {
        HStack(spacing: 16) {
            StatMiniCard(
                icon: "figure.walk",
                title: "Шаги сегодня",
                value: "\(Int(model.stepsToday))",
                color: .blue
            )
            
            StatMiniCard(
                icon: "shoeprints.fill",
                title: "Баланс шагов",
                value: "\(model.stepsBalance)",
                color: .green
            )
            
            StatMiniCard(
                icon: "creditcard",
                title: "Стоимость входа",
                value: "\(model.entryCostSteps)",
                color: .orange
            )
        }
    }
    
    // MARK: - Big Time Display
    private var bigTimeDisplayView: some View {
        VStack(spacing: 12) {
            if model.isBlocked {
                VStack(spacing: 8) {
                    Text("⏰")
                        .font(.system(size: 60))
                    
                    Text("Время прошло!")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }
            } else {
                VStack(spacing: 8) {
                    Text("Осталось")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    
                    Text("\(calculatedRemainingMinutes)")
                        .font(.system(size: 80, weight: .bold, design: .rounded))
                        .foregroundColor(timeColor)
                        .contentTransition(.numericText())
                    
                    Text(calculatedRemainingMinutes == 1 ? "минута" : "минут")
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
                Text("Использовано времени")
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
    
    // MARK: - Control Buttons
    private var controlButtonsView: some View {
        VStack(spacing: 12) {
            // Основная кнопка управления
            Button(model.isTrackingTime ? "🔓 Остановить отслеживание" : "🛡️ Начать отслеживание") {
                model.toggleRealBlocking()
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(model.isTrackingTime ? Color.red : Color.blue)
            .foregroundColor(.white)
            .font(.headline)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .disabled(!model.familyControlsService.isAuthorized || 
                     (!model.isTrackingTime && model.remainingMinutes <= 0) ||
                     (model.appSelection.applicationTokens.isEmpty && model.appSelection.categoryTokens.isEmpty))
            
            // Предупреждение если нет времени
            if !model.isTrackingTime && model.remainingMinutes <= 0 {
                Text("⚠️ Нет доступного времени! Сделайте больше шагов.")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
            }
            
            // Предупреждение если приложение не выбрано
            if model.appSelection.applicationTokens.isEmpty && model.appSelection.categoryTokens.isEmpty {
                Text("⚠️ Выберите приложение в настройках")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
    }
    
    // MARK: - Computed Properties
    private var remainingStepsToday: Int {
        let spentSteps = model.spentMinutes * Int(model.spentTariff.stepsPerMinute)
        return max(0, Int(model.stepsToday) - spentSteps)
    }
    
    private var calculatedRemainingMinutes: Int {
        return max(0, model.dailyBudgetMinutes - model.spentMinutes)
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
    
    private func formatTime(minutes: Int) -> String {
        return "\(minutes) мин"
    }
    
    // MARK: - Timer Management
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            // Принудительно обновляем бюджет из хранилища
            model.reloadBudgetFromStorage()
            
            // Принудительно обновляем потраченное время
            model.loadSpentTime()
            
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
            model.message = "⏰ Время истекло!"
            
            // Применяем реальную блокировку приложений
            if let familyService = model.familyControlsService as? FamilyControlsService {
                familyService.enableShield()
                print("🛡️ Applied real app blocking via ManagedSettings")
            }
            
            // Отправляем уведомления с количеством минут, которое было доступно
            model.notificationService.sendTimeExpiredNotification(remainingMinutes: minutesBeforeBlocking);            model.sendReturnToAppNotification()
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
        model.message = "✅ Время восстановлено! Доступно: \(calculatedRemainingMinutes) мин"
        
        // Снимаем реальную блокировку приложений
        if let familyService = model.familyControlsService as? FamilyControlsService {
            familyService.disableShield()
            print("🔓 Removed app blocking via ManagedSettings")
        }
        
        // Отправляем уведомление о разблокировке
        model.notificationService.sendUnblockNotification(remainingMinutes: calculatedRemainingMinutes)
        AudioServicesPlaySystemSound(1003) // Success sound
    }
    
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func sendRemainingTimeNotificationIfNeeded() {
        // Отправляем уведомление только если время меньше 10 минут и больше 0
        // И только если минуты изменились (чтобы не спамить)
        if calculatedRemainingMinutes > 0 && calculatedRemainingMinutes < 10 && calculatedRemainingMinutes != lastNotificationMinutes {
            model.notificationService.sendRemainingTimeNotification(remainingMinutes: calculatedRemainingMinutes)
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
                    if let appStoreURL = URL(string: "https://apps.apple.com/app/instagram/id389801252") {
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
