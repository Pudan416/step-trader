import SwiftUI
import HealthKit
import Combine

@main
struct StepTimeLimiterApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

// MARK: - ContentView
struct ContentView: View {
    @StateObject var model = AppModel()
    @State private var showAppSelector = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Анимированный заголовок с градиентом
                    HStack(spacing: 8) {
                        Text("👟")
                            .font(.title)
                            .scaleEffect(1.2)
                            .rotationEffect(.degrees(model.isTrackingTime ? 15 : 0))
                            .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: model.isTrackingTime)
                        
                        Text("Step Trader")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .purple, .pink],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        Text("⚡")
                            .font(.title)
                            .scaleEffect(1.2)
                            .opacity(model.isTrackingTime ? 1.0 : 0.6)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: model.isTrackingTime)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 15)
                    .padding(.bottom, 5)
                    
                    // Основная статистика в формате 2x2
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ], spacing: 15) {
                        // Количество шагов
                        StatCard(
                            title: "Шаги сегодня",
                            value: Int(model.stepsToday).formatted(),
                            icon: "👟",
                            color: .green
                        )
                        
                        // Потрачено шагов
                        StatCard(
                            title: "Потрачено шагов",
                            value: model.spentSteps.formatted(),
                            icon: "📱",
                            color: .orange
                        )
                        
                        // Бюджет минут
                        StatCard(
                            title: "Бюджет минут",
                            value: model.budget.dailyBudgetMinutes.formatted(),
                            icon: "⏰",
                            color: .blue
                        )
                        
                        // Осталось минут
                        StatCard(
                            title: "Осталось минут",
                            value: model.budget.remainingMinutes.formatted(),
                            icon: "⏳",
                            color: model.budget.remainingMinutes > 0 ? .green : .red
                        )
                    }
                    .padding(.horizontal)
                    
                    // Прогресс бар
                    VStack(spacing: 8) {
                        HStack {
                            Text("Использование времени")
                                .font(.headline)
                            Spacer()
                            Text("\(model.budget.dailyBudgetMinutes - model.budget.remainingMinutes)/\(model.budget.dailyBudgetMinutes) мин")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        ProgressView(
                            value: Double(max(0, model.budget.dailyBudgetMinutes - model.budget.remainingMinutes)),
                            total: Double(max(1, model.budget.dailyBudgetMinutes))
                        )
                        .progressViewStyle(LinearProgressViewStyle(tint: model.budget.remainingMinutes > 0 ? .blue : .red))
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                    .padding(.horizontal)
                    
                    // Выбор сложности
                    VStack(spacing: 12) {
                        HStack {
                            Text("Уровень сложности")
                                .font(.headline)
                            Spacer()
                            Text("\(Int(model.budget.difficultyLevel.stepsPerMinute)) шагов/мин")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Picker("Сложность", selection: Binding(
                            get: { model.budget.difficultyLevel },
                            set: { model.budget.difficultyLevel = $0 }
                        )) {
                            ForEach(DifficultyLevel.allCases, id: \.self) { level in
                                Text(level.rawValue).tag(level)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                    .padding(.horizontal)
                    
                    // Выбранные приложения
                    VStack(spacing: 12) {
                        HStack {
                            Text("Отслеживаемые приложения")
                                .font(.headline)
                            Spacer()
                            Button("Выбрать") {
                                showAppSelector = true
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        
                        if model.selectedApps.isEmpty {
                            Text("Приложения не выбраны")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        } else {
                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: 8) {
                                ForEach(model.selectedApps, id: \.self) { app in
                                    HStack(spacing: 4) {
                                        Text(app.icon)
                                            .font(.caption)
                                        Text(app.name)
                                            .font(.caption2)
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 4)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(.blue.opacity(0.1)))
                                }
                            }
                        }
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                    .padding(.horizontal)
                    
                    // Информация о текущем отслеживании
                    if model.isTrackingTime {
                        VStack(spacing: 8) {
                            HStack {
                                Text("🔴")
                                Text("Отслеживание активно")
                                    .font(.headline)
                                    .foregroundColor(.red)
                                Spacer()
                            }
                            
                            HStack {
                                Text("Приложения:")
                                ForEach(model.selectedApps.prefix(3), id: \.self) { app in
                                    Text(app.icon)
                                }
                                if model.selectedApps.count > 3 {
                                    Text("+\(model.selectedApps.count - 3)")
                                        .font(.caption2)
                                }
                                Spacer()
                                if let elapsed = model.currentSessionElapsed {
                                    Text("Сессия: \(elapsed) мин")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 16).fill(.red.opacity(0.1)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(.red.opacity(0.3), lineWidth: 1)
                        )
                        .padding(.horizontal)
                    }
                    
                    // Кнопки управления
                    VStack(spacing: 12) {
                        Button("🔄 Пересчитать бюджет") {
                            Task { try? await model.recalc() }
                        }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        
                        Button(model.isTrackingTime ? "⏸️ Остановить отслеживание" : "▶️ Начать отслеживание") {
                            model.toggleTimeTracking()
                        }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(model.selectedApps.isEmpty)
                    }
                    .padding(.horizontal)
                    
                    Spacer(minLength: 20)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .task { await model.bootstrap() }
            .alert("Информация", isPresented: Binding(get: { model.message != nil }, set: { _ in model.message = nil })) {
                Button("OK", role: .cancel) {}
            } message: { Text(model.message ?? "") }
            .sheet(isPresented: $showAppSelector) {
                AppSelectorView(
                    availableApps: model.installedApps,
                    selectedApps: $model.selectedApps
                )
            }
        }
    }
}

// MARK: - App Selector View
struct AppSelectorView: View {
    let availableApps: [TrackedApp]
    @Binding var selectedApps: [TrackedApp]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                if availableApps.isEmpty {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text("Целевые приложения не установлены")
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                } else {
                    Section("Установленные приложения") {
                        ForEach(availableApps, id: \.self) { app in
                            HStack {
                                Text(app.icon)
                                    .font(.title2)
                                Text(app.name)
                                Spacer()
                                if selectedApps.contains(app) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if let index = selectedApps.firstIndex(of: app) {
                                    selectedApps.remove(at: index)
                                } else {
                                    selectedApps.append(app)
                                }
                            }
                        }
                    }
                }
                
                Section("Информация") {
                    Text("Выбранные приложения будут отслеживаться совместно. Время будет тратиться из общего бюджета.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Выбор приложений")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - App Model
struct TrackedApp: Hashable {
    let name: String
    let icon: String
    let bundleId: String
}

// MARK: - AppModel
@MainActor
final class AppModel: ObservableObject {
    let hk = HealthKitService()
    let budget = BudgetEngine()
    
    @Published var stepsToday: Double = 0
    @Published var spentSteps: Int = 0
    @Published var isTrackingTime = false
    @Published var message: String?
    @Published var selectedApps: [TrackedApp] = []
    @Published var currentSessionElapsed: Int?
    @Published var installedApps: [TrackedApp] = []
    
    private let targetApps = [
        TrackedApp(name: "Instagram", icon: "📷", bundleId: "com.burbn.instagram"),
        TrackedApp(name: "TikTok", icon: "🎵", bundleId: "com.zhiliaoapp.musically"),
        TrackedApp(name: "YouTube", icon: "▶️", bundleId: "com.google.ios.youtube")
    ]
    
    private var startTime: Date?
    private var timer: Timer?

    func bootstrap() async {
        do {
            try await hk.requestAuthorization()
            checkInstalledApps()
            try await recalc()
        } catch {
            self.message = "Ошибка: \(error.localizedDescription)"
        }
    }
    
    private func checkInstalledApps() {
        // Для демо показываем все приложения как установленные
        self.installedApps = targetApps
    }

    func recalc() async throws {
        budget.resetIfNeeded()
        stepsToday = try await hk.fetchTodaySteps()
        let mins = budget.minutes(from: stepsToday)
        budget.setBudget(minutes: mins)
        
        // Рассчитываем потраченные шаги на основе использованного времени
        let usedMinutes = budget.dailyBudgetMinutes - budget.remainingMinutes
        spentSteps = usedMinutes * Int(budget.difficultyLevel.stepsPerMinute)
        
        message = "Бюджет обновлен: \(mins) минут из \(Int(stepsToday)) шагов"
    }
    
    func toggleTimeTracking() {
        if isTrackingTime {
            stopTracking()
        } else {
            startTracking()
        }
    }
    
    private func startTracking() {
        guard budget.remainingMinutes > 0 else {
            message = "Нет доступного времени! Сделайте больше шагов."
            return
        }
        
        guard !selectedApps.isEmpty else {
            message = "Выберите приложения для отслеживания."
            return
        }
        
        isTrackingTime = true
        startTime = Date()
        currentSessionElapsed = 0
        
        let appNames = selectedApps.map { $0.name }.joined(separator: ", ")
        message = "Отслеживание (\(appNames)) начато. Доступно: \(budget.remainingMinutes) мин"
        
        // Таймер каждую минуту
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateTimeSpent()
            }
        }
    }
    
    private func stopTracking() {
        isTrackingTime = false
        timer?.invalidate()
        timer = nil
        
        if let start = startTime {
            let elapsed = Int(Date().timeIntervalSince(start) / 60)
            budget.consume(mins: elapsed)
            
            // Обновляем потраченные шаги
            let usedMinutes = budget.dailyBudgetMinutes - budget.remainingMinutes
            spentSteps = usedMinutes * Int(budget.difficultyLevel.stepsPerMinute)
            
            let appNames = selectedApps.map { $0.name }.joined(separator: ", ")
            message = "Отслеживание (\(appNames)) остановлено. Потрачено: \(elapsed) мин. Осталось: \(budget.remainingMinutes) мин"
        }
        
        startTime = nil
        currentSessionElapsed = nil
    }
    
    private func updateTimeSpent() {
        guard let start = startTime else { return }
        
        let elapsed = Int(Date().timeIntervalSince(start) / 60)
        currentSessionElapsed = elapsed
        
        budget.consume(mins: 1) // Списываем 1 минуту
        
        // Обновляем потраченные шаги
        let usedMinutes = budget.dailyBudgetMinutes - budget.remainingMinutes
        spentSteps = usedMinutes * Int(budget.difficultyLevel.stepsPerMinute)
        
        if budget.remainingMinutes <= 0 {
            let appNames = selectedApps.map { $0.name }.joined(separator: ", ")
            stopTracking()
            message = "⏰ Время для (\(appNames)) истекло! Сделайте больше шагов для получения дополнительного времени."
        }
    }
}

// MARK: - StatCard
struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(icon)
                    .font(.title2)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(color)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .frame(height: 100)
        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
}
