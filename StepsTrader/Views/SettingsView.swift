import SwiftUI
import FamilyControls

// MARK: - SettingsView
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var isPickerPresented = false
    
    var body: some View {
        NavigationView {
            Form {
                // 0. Шкала остатка шагов
                remainingStepsSection
                
                // 1. Секция тарифа (сначала)
                tariffSection
                
                // 2. Секция выбора приложения
                appSelectionSection
                
                // 3. Секция отслеживания (кнопка начать/остановить)
                trackingSection
                
                // 4. Секция управления
                managementSection
                
                // 5. Секция статуса системы
                systemStatusSection
            }
        }
    }
    
    // MARK: - Computed Properties
    private var remainingStepsToday: Int {
        let spentSteps = model.spentMinutes * Int(model.budget.stepsPerMinute)
        return max(0, Int(model.stepsToday) - spentSteps)
    }
    
    private func isTariffAvailable(_ tariff: Tariff) -> Bool {
        let requiredSteps = Int(tariff.stepsPerMinute)
        return remainingStepsToday >= requiredSteps
    }
    
    // MARK: - Remaining Steps Section
    private var remainingStepsSection: some View {
        Section {
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
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - App Selection Section (пользователь выбирает в системном списке)
    private var appSelectionSection: some View {
        Section("Выбор приложения для отслеживания") {
            VStack(alignment: .leading, spacing: 12) {
                // Подсказка из Shortcuts
                if let desired = getAutoSelectedApp() {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lightbulb.fill").foregroundColor(.yellow)
                        Text("Из шортката: выберите \(desired) в системном списке ниже")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Текущее состояние выбора
                if !model.appSelection.applicationTokens.isEmpty || !model.appSelection.categoryTokens.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                        Text("Выбрано: \(model.appSelection.applicationTokens.isEmpty ? "категория" : "приложение")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                        Text("Пока не выбрано ни одного приложения")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }

                // Кнопка для открытия системного FamilyActivityPicker
                Button("Выбрать приложение из списка") {
                    isPickerPresented = true
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding(.vertical, 8)
        }
        .sheet(isPresented: $isPickerPresented) {
            NavigationView {
                FamilyActivityPicker(selection: $model.appSelection)
                    .navigationTitle("Выбор приложений")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Готово") { isPickerPresented = false }
                        }
                    }
            }
            .ignoresSafeArea()
        }
        // Авто‑закрытие как только пользователь что‑то выбрал
        .onChange(of: model.appSelection.applicationTokens.count) { _, newValue in
            if newValue > 0 || model.appSelection.categoryTokens.count > 0 {
                isPickerPresented = false
            }
        }
        .onChange(of: model.appSelection.categoryTokens.count) { _, newValue in
            if newValue > 0 || model.appSelection.applicationTokens.count > 0 {
                isPickerPresented = false
            }
        }
        
    }
    
    // MARK: - Tariff Section
    private var tariffSection: some View {
        Section("Тариф обмена") {
            VStack(alignment: .leading, spacing: 16) {
                Text("Выберите сколько шагов нужно для получения 1 минуты времени:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ForEach(Tariff.allCases, id: \.self) { tariff in
                    TariffOptionView(
                        tariff: tariff,
                        isSelected: model.budget.tariff == tariff,
                        isDisabled: !isTariffAvailable(tariff)
                    ) {
                        selectTariff(tariff)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Tracking Section
    private var trackingSection: some View {
        Section("Отслеживание времени") {
            VStack(spacing: 16) {
                
                
                // Показать информацию об автовыборе
                if let autoSelected = getAutoSelectedApp() {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Автоматически выбрано: \(autoSelected)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                
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
                
                // Статус отслеживания
                if model.isTrackingTime {
                    HStack {
                        Image(systemName: "circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text("Отслеживание активно")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
                
                // Предупреждения
                VStack(spacing: 8) {
                    if !model.isTrackingTime && model.remainingMinutes <= 0 {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Нет доступного времени! Сделайте больше шагов.")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    
                    if model.appSelection.applicationTokens.isEmpty && model.appSelection.categoryTokens.isEmpty {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Сначала выберите приложение выше")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    
                    if !model.familyControlsService.isAuthorized {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text("Family Controls не авторизован")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Management Section
    private var managementSection: some View {
        Section("Управление") {
            VStack(spacing: 12) {
                Button("🔄 Пересчитать бюджет") {
                    Task {
                        await model.recalcSilently()
                        model.message = "✅ Бюджет пересчитан"
                    }
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.bordered)
                
                Button("🗑️ Сбросить статистику") {
                    model.resetStatistics()
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.bordered)
                .foregroundColor(.orange)
                
                Button("🔍 Диагностика") {
                    model.runDiagnostics()
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
        Section("Статус системы") {
            VStack(alignment: .leading, spacing: 12) {
                StatusRow(
                    icon: "heart.fill",
                    title: "HealthKit",
                    status: .connected,
                    description: "Доступ к данным о шагах"
                )
                
                StatusRow(
                    icon: "shield.fill",
                    title: "Family Controls",
                    status: model.familyControlsService.isAuthorized ? .connected : .disconnected,
                    description: model.familyControlsService.isAuthorized ? "Блокировка приложений активна" : "Требуется авторизация"
                )
                
                StatusRow(
                    icon: "bell.fill",
                    title: "Уведомления",
                    status: .connected,
                    description: "Push-уведомления включены"
                )
                
                if !model.familyControlsService.isAuthorized {
                    Button("🔐 Запросить Family Controls") {
                        Task {
                            do {
                                try await model.familyControlsService.requestAuthorization()
                                model.message = "✅ Family Controls авторизация запрошена"
                            } catch {
                                model.message = "❌ Ошибка авторизации: \(error.localizedDescription)"
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.borderedProminent)
                    .foregroundColor(.white)
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Actions
    private func selectTariff(_ tariff: Tariff) {
        model.budget.updateTariff(tariff)
        
        // Пересчитываем бюджет с новым тарифом
        Task {
            await model.recalcSilently()
            await MainActor.run {
                model.message = "✅ Тариф изменен на \(tariff.displayName)"
            }
        }
    }
    
    private func getPendingShortcutApp() -> String? {
        let userDefaults = UserDefaults.stepsTrader()
        guard let bundleId = userDefaults.string(forKey: "pendingShortcutApp") else {
            return nil
        }
        
        switch bundleId {
        case "com.burbn.instagram": return "Instagram"
        case "com.zhiliaoapp.musically": return "TikTok"
        case "com.google.ios.youtube": return "YouTube"
        default: return bundleId
        }
    }
    
    private func getAutoSelectedApp() -> String? {
        let userDefaults = UserDefaults.stepsTrader()
        guard let bundleId = userDefaults.string(forKey: "autoSelectedAppBundleId") else {
            return nil
        }
        
        switch bundleId {
        case "com.burbn.instagram": return "Instagram"
        case "com.zhiliaoapp.musically": return "TikTok"
        case "com.google.ios.youtube": return "YouTube"
        default: return bundleId
        }
    }
}
