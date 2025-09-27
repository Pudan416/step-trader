import SwiftUI

// MARK: - Block Screen
struct BlockScreen: View {
    @ObservedObject var model: AppModel
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [.red.opacity(0.1), .orange.opacity(0.3), .red.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 30) {
                // Icon and title
                VStack(spacing: 16) {
                    Text("⏰")
                        .font(.system(size: 80))
                    
                    Text("Время истекло!")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                    
                    Text("Ваше время для развлечений закончилось")
                        .font(.title2)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }
                
                // Stats
                VStack(spacing: 12) {
                    HStack {
                        Text("Потрачено времени:")
                        Spacer()
                        Text(formatTime(minutes: model.spentMinutes))
                            .fontWeight(.semibold)
                    }
                    
                    HStack {
                        Text("Потрачено шагов:")
                        Spacer()
                        Text("\(model.spentSteps)")
                            .fontWeight(.semibold)
                    }
                    
                    Divider()
                    
                    HStack {
                        Text("Шагов сегодня:")
                        Spacer()
                        Text("\(Int(model.stepsToday))")
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                
                // Action buttons
                VStack(spacing: 12) {
                    Text("Чтобы получить больше времени:")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    
                    Text("🚶‍♂️ Сделайте больше шагов")
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                    
                    Text("\(Int(model.budget.tariff.stepsPerMinute)) шагов = 1 минута развлечений")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Bottom buttons
                VStack(spacing: 12) {
                    Button("🔄 Обновить баланс") {
                        Task {
                            do {
                                try await model.recalc()
                                // Если появились новые минуты, снимаем блокировку
                                if model.remainingMinutes > 0 {
                                    model.isBlocked = false
                                    model.message = "✅ Время восстановлено! Доступно: \(model.remainingMinutes) мин"
                                } else {
                                    model.message = "❌ Недостаточно шагов для разблокировки"
                                }
                            } catch {
                                model.message = "❌ Ошибка обновления: \(error.localizedDescription)"
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    
                    Button("❌ Завершить сессию") {
                        model.stopTracking()
                        model.isBlocked = false
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .foregroundColor(.red)
                    
                    Button("🗑️ Сбросить всю статистику") {
                        model.resetStatistics()
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .foregroundColor(.orange)
                }
            }
            .padding()
        }
    }
    
    private func formatTime(minutes: Int) -> String {
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        
        if hours > 0 {
            return "\(hours)ч \(remainingMinutes)мин"
        } else {
            return "\(remainingMinutes)мин"
        }
    }
}
