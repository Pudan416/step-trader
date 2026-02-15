import SwiftUI

struct DailyEnergyCard: View {
    @ObservedObject var model: AppModel
    @AppStorage("userStepsTarget") private var userStepsTarget: Double = 10_000
    @AppStorage("userSleepTarget") private var userSleepTarget: Double = 8.0
    @State private var showMoveSettings = false
    @State private var showCreativitySettings = false
    @State private var showJoySettings = false
    
    private var sleepBinding: Binding<Double> {
        Binding(
            get: { model.healthStore.dailySleepHours },
            set: { model.setDailySleepHours($0) }
        )
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            activitySection
            creativitySection
            joysSection
        }
        .padding(20)
        .background(glassCard)
        .sheet(isPresented: $showMoveSettings) {
            CategorySettingsView(model: model, category: .body)
        }
        .sheet(isPresented: $showCreativitySettings) {
            CategorySettingsView(model: model, category: .mind)
        }
        .sheet(isPresented: $showJoySettings) {
            CategorySettingsView(model: model, category: .heart)
        }
    }
    
    // MARK: - Glass Card Style
    private var glassCard: some View {
        RoundedRectangle(cornerRadius: 24)
            .stroke(Color.primary.opacity(0.2), lineWidth: 1)
    }
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("Daily Exp")
                    .font(.title3.weight(.bold))
                Text("Build 100 points from activity, creativity, and joys")
                    .font(.caption)
                    .foregroundColor(.primary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(model.healthStore.baseEnergyToday)")
                    .font(.notoSerif(32, weight: .bold))
                    .foregroundColor(.primary)
                    .monospacedDigit()
                Text("/\(EnergyDefaults.maxBaseEnergy)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
            }
        }
    }
    
    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: "Body",
                points: model.activityPointsToday,
                maxPoints: 20,
                category: .body
            )
            
            optionGrid(
                options: model.preferredOptions(for: .body),
                category: .body
            )
        }
    }
    
    private var creativitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: "Mind",
                points: model.creativityPointsToday,
                maxPoints: 20,
                category: .mind
            )
            
            optionGrid(
                options: model.preferredOptions(for: .mind),
                category: .mind
            )
        }
    }
    
    private var joysSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: "Heart",
                points: model.joysCategoryPointsToday,
                maxPoints: 20,
                category: .heart
            )
            
            optionGrid(
                options: model.preferredOptions(for: .heart),
                category: .heart
            )
        }
    }
    
    private func sectionHeader(title: String, points: Int, maxPoints: Int, category: EnergyCategory) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text("\(points)/\(maxPoints)")
                .font(.caption.weight(.bold))
                        .foregroundColor(.primary)
            
            Button {
                if category == .body {
                    showMoveSettings = true
                } else if category == .mind {
                    showCreativitySettings = true
                } else if category == .heart {
                    showJoySettings = true
                }
            } label: {
                Image(systemName: "pencil.circle.fill")
                    .font(.title3)
                    .foregroundColor(.blue)
            }
        }
    }
    
    @ViewBuilder
    private func optionGrid(options: [EnergyOption], category: EnergyCategory) -> some View {
        if options.isEmpty {
            Text("No options selected")
                .font(.caption)
                    .foregroundColor(.primary)
        } else {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(options) { option in
                    optionChip(option: option, category: category)
                }
            }
        }
    }
    
    private func optionChip(option: EnergyOption, category: EnergyCategory) -> some View {
        let isSelected = model.isDailySelected(option.id, category: category)
        let chipColor: Color = {
            switch category {
            case .body: return .green
            case .mind: return .purple
            case .heart: return .orange
            }
        }()
        
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                model.toggleDailySelection(optionId: option.id, category: category)
            }
        } label: {
            HStack(spacing: 8) {
                // Icon
                Image(systemName: option.icon)
                    .font(.caption)
                    .foregroundColor(isSelected ? .white : chipColor)
                    .frame(width: 20)
                
                Text(option.title(for: "en"))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(isSelected ? .white : .primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? 
                          LinearGradient(colors: [chipColor, chipColor.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing) :
                          LinearGradient(colors: [Color(.secondarySystemBackground)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isSelected ? Color.white.opacity(0.2) : Color.clear, lineWidth: 1)
                    )
            )
            .shadow(color: isSelected ? chipColor.opacity(0.2) : Color.clear, radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
    
    private func formatNumber(_ value: Int) -> String {
        value < 1000 ? "\(value)" : "\(value / 1000)k"
    }
}
