import SwiftUI

// MARK: - TariffOptionView Component
struct TariffOptionView: View {
    let tariff: Tariff
    let isSelected: Bool
    let isDisabled: Bool
    let stepsToday: Double
    let action: () -> Void
    
    init(tariff: Tariff, isSelected: Bool, isDisabled: Bool = false, stepsToday: Double = 0, action: @escaping () -> Void) {
        self.tariff = tariff
        self.isSelected = isSelected
        self.isDisabled = isDisabled
        self.stepsToday = stepsToday
        self.action = action
    }
    
    var body: some View {
        Button(action: isDisabled ? {} : action) {
            HStack(spacing: 16) {
                // Иконка тарифа
                Text(tariffIcon)
                    .font(.title2)
                    .opacity(isDisabled ? 0.5 : 1.0)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(tariff.displayName)
                        .font(.headline)
                        .foregroundColor(isDisabled ? .secondary : .primary)
                    
                    Text(isDisabled ? "Недостаточно шагов" : tariff.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if !isDisabled && stepsToday > 0 {
                        Text("Получите: \(minutesFromSteps) мин")
                            .font(.caption)
                            .foregroundColor(.blue)
                            .fontWeight(.medium)
                    }
                }
                
                Spacer()
                
                // Индикатор выбора или блокировки
                if isDisabled {
                    Image(systemName: "lock.fill")
                        .foregroundColor(.red)
                        .font(.title2)
                } else {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .blue : .gray)
                        .font(.title2)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue.opacity(0.1) : (isDisabled ? Color.gray.opacity(0.1) : Color.clear))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.blue : (isDisabled ? Color.red.opacity(0.3) : Color.gray.opacity(0.3)), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isDisabled)
    }
    
    private var tariffIcon: String {
        switch tariff {
        case .easy: return "💎"
        case .medium: return "🔥"
        case .hard: return "💪"
        }
    }
    
    private var minutesFromSteps: Int {
        // Рассчитываем минуты на основе всех шагов за день, а не оставшихся
        return max(0, Int(stepsToday / tariff.stepsPerMinute))
    }
}
