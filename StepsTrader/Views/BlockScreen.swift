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
                        .font(.notoSerif(80))
                    
                    Text("Time's up")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                    
                    Text("My call")
                        .font(AppFonts.title2)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }
                
                // Stats
                VStack(spacing: 12) {
                    HStack {
                        Text("Time spent")
                        Spacer()
                        Text(formatTime(minutes: model.spentMinutes))
                            .fontWeight(.semibold)
                    }
                    
                    HStack {
                        Text("Experience spent")
                        Spacer()
                        Text("\(model.spentSteps)")
                            .fontWeight(.semibold)
                    }
                    
                    Divider()
                    
                    HStack {
                        Text("Experience today")
                        Spacer()
                        Text("\(model.baseEnergyToday)")
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                
                // Action buttons
                VStack(spacing: 12) {
                    Text("Do whatever I want")
                        .font(AppFonts.headline)
                        .multilineTextAlignment(.center)
                    
                    Text("Get more experience")
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                    
                    Text("\(Int(model.spentTariff.stepsPerMinute)) experience = 1 minute")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Bottom buttons
                VStack(spacing: 12) {
                    Button("Refresh") {
                        Task {
                            await model.recalcSilently()
                            if model.remainingMinutes > 0 {
                                model.isBlocked = false
                                model.message = "Available: \(model.remainingMinutes) min"
                            } else {
                                model.message = "Not enough experience"
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    
                    Button("End session") {
                        model.stopTracking()
                        model.isBlocked = false
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .foregroundColor(.red)
                    
                    Button("Reset stats") {
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
