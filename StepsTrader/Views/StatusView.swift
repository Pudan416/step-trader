import SwiftUI

// MARK: - StatusView
struct StatusView: View {
    @ObservedObject var model: AppModel
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Полоса с остатком шагов сверху
                    remainingStepsBarView
                    
                    // Мини-статистика
                    miniStatsView
                    
                    // Большое отображение времени в центре
                    bigTimeDisplayView
                    
                    // Прогресс-бар
                    progressBarView
                    
                    Spacer(minLength: 20)
                }
                .padding()
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
    
    // MARK: - Mini Stats
    private var miniStatsView: some View {
        HStack(spacing: 16) {
            StatMiniCard(
                icon: "figure.walk",
                title: "Шаги сегодня",
                value: "\(Int(model.stepsToday))",
                color: .blue
            )
            
            StatMiniCard(
                icon: "clock",
                title: "Всего минут",
                value: "\(model.dailyBudgetMinutes)",
                color: .green
            )
            
            StatMiniCard(
                icon: "timer",
                title: "Потрачено",
                value: formatTime(minutes: model.spentMinutes),
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
                    
                    Text("\(model.remainingMinutes)")
                        .font(.system(size: 80, weight: .bold, design: .rounded))
                        .foregroundColor(timeColor)
                        .contentTransition(.numericText())
                    
                    Text(model.remainingMinutes == 1 ? "минута" : "минут")
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
        let spentSteps = model.spentMinutes * Int(model.budget.stepsPerMinute)
        return max(0, Int(model.stepsToday) - spentSteps)
    }
    
    private var timeColor: Color {
        let percentage = progressValue
        if percentage >= 0.9 {
            return .red
        } else if percentage >= 0.7 {
            return .orange
        } else {
            return .green
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
        if minutes < 60 {
            return "\(minutes)м"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return "\(hours)ч \(remainingMinutes)м"
        }
    }
}
