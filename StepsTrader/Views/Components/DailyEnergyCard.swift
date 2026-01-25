import SwiftUI

struct DailyEnergyCard: View {
    @ObservedObject var model: AppModel
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    
    private var sleepBinding: Binding<Double> {
        Binding(
            get: { model.dailySleepHours },
            set: { model.setDailySleepHours($0) }
        )
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            recoverySection
            activitySection
            joySection
        }
        .padding(20)
        .background(glassCard)
    }
    
    // MARK: - Glass Card Style
    private var glassCard: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.3), Color.white.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: Color.black.opacity(0.06), radius: 16, x: 0, y: 6)
    }
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(loc(appLanguage, "Daily Energy", "Энергия дня"))
                    .font(.title3.weight(.bold))
                Text(loc(appLanguage, "Build 100 points from recovery, activity, and joy", "Собери 100 баллов из восстановления, активности и радости"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(model.baseEnergyToday)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.orange, .pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .monospacedDigit()
                Text("/\(EnergyDefaults.maxBaseEnergy)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var recoverySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: loc(appLanguage, "Recovery", "Восстановление"),
                points: model.recoveryPointsToday,
                maxPoints: 40
            )
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(loc(appLanguage, "Sleep", "Сон"))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(model.sleepPointsToday)/\(EnergyDefaults.sleepMaxPoints)")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 12) {
                    Slider(value: sleepBinding, in: 0...12, step: 0.5)
                    Text(String(format: "%.1fh", model.dailySleepHours))
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
            }
            
            optionGrid(
                options: model.preferredOptions(for: .recovery),
                category: .recovery
            )
        }
    }
    
    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: loc(appLanguage, "Activity", "Активность"),
                points: model.activityPointsToday,
                maxPoints: 40
            )
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(loc(appLanguage, "Steps", "Шаги"))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(model.stepsPointsToday)/\(EnergyDefaults.stepsMaxPoints)")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.secondary)
                }
                Text("\(formatNumber(Int(model.stepsToday)))/\(formatNumber(Int(EnergyDefaults.stepsTarget)))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            optionGrid(
                options: model.preferredOptions(for: .activity),
                category: .activity
            )
        }
    }
    
    private var joySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: loc(appLanguage, "Joy", "Радость"),
                points: model.joyCategoryPointsToday,
                maxPoints: 20
            )
            
            optionGrid(
                options: model.preferredOptions(for: .joy),
                category: .joy
            )
        }
    }
    
    private func sectionHeader(title: String, points: Int, maxPoints: Int) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text("\(points)/\(maxPoints)")
                .font(.caption.weight(.bold))
                .foregroundColor(.secondary)
        }
    }
    
    @ViewBuilder
    private func optionGrid(options: [EnergyOption], category: EnergyCategory) -> some View {
        if options.isEmpty {
            Text(loc(appLanguage, "No options selected", "Список пуст"))
                .font(.caption)
                .foregroundColor(.secondary)
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
            case .recovery: return .blue
            case .activity: return .green
            case .joy: return .orange
            }
        }()
        
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                model.toggleDailySelection(optionId: option.id, category: category)
            }
        } label: {
            HStack(spacing: 8) {
                Text(option.title(for: appLanguage))
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
