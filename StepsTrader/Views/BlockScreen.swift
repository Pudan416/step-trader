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
                    
                    Text("Time's up")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                    
                    Text("Your call")
                        .font(.title2)
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
                        Text("Control spent")
                        Spacer()
                        Text("\(model.spentSteps)")
                            .fontWeight(.semibold)
                    }
                    
                    Divider()
                    
                    HStack {
                        Text("Control today")
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
                    Text("Do whatever you want")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    
                    Text("Get more control")
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                    
                    Text("\(Int(model.spentTariff.stepsPerMinute)) control = 1 minute")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Bottom buttons
                VStack(spacing: 12) {
                    Button("Refresh") {
                        Task {
                            do {
                                try await model.recalc()
                                if model.remainingMinutes > 0 {
                                    model.isBlocked = false
                                    model.message = "Available: \(model.remainingMinutes) min"
                                } else {
                                    model.message = "Not enough control"
                                }
                            } catch {
                                model.message = "Refresh failed"
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
