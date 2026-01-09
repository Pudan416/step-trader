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
                    
                    Text("Time's up!")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                    
                    Text("Your entertainment time has run out")
                        .font(.title2)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }
                
                // Stats
                VStack(spacing: 12) {
                    HStack {
                        Text("Time spent:")
                        Spacer()
                        Text(formatTime(minutes: model.spentMinutes))
                            .fontWeight(.semibold)
                    }
                    
                    HStack {
                        Text("Steps spent:")
                        Spacer()
                        Text("\(model.spentSteps)")
                            .fontWeight(.semibold)
                    }
                    
                    Divider()
                    
                    HStack {
                        Text("Steps today:")
                        Spacer()
                        Text("\(Int(model.effectiveStepsToday))")
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                
                // Action buttons
                VStack(spacing: 12) {
                    Text("To get more time:")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    
                    Text("🚶‍♂️ Walk more steps")
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                    
                    Text("\(Int(model.budget.tariff.stepsPerMinute)) steps = 1 minute of fun")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Bottom buttons
                VStack(spacing: 12) {
                    Button("🔄 Refresh balance") {
                        Task {
                            do {
                                try await model.recalc()
                                // Если появились новые минуты, снимаем блокировку
                                if model.remainingMinutes > 0 {
                                    model.isBlocked = false
                                    model.message = "✅ Time restored! Available: \(model.remainingMinutes) min"
                                } else {
                                    model.message = "❌ Not enough steps to unlock"
                                }
                            } catch {
                                model.message = "❌ Refresh failed: \(error.localizedDescription)"
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    
                    Button("❌ End session") {
                        model.stopTracking()
                        model.isBlocked = false
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .foregroundColor(.red)
                    
                    Button("🗑️ Reset all stats") {
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
        return "\(minutes) min"
    }
}
