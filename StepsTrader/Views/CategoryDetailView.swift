import SwiftUI

struct CategoryDetailView: View {
    @ObservedObject var model: AppModel
    let category: EnergyCategory?
    let outerWorldSteps: Int
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @State private var showSettings = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 24) {
                    // Header with points
                    headerSection
                    
                    // Content based on category
                    if let category = category {
                        categoryContent(category: category)
                    } else {
                        outerWorldContent
                    }
                    
                    // Edit button at bottom
                    editButton
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .background(theme.backgroundColor)
            .navigationTitle(categoryTitle)
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showSettings) {
                if let category = category {
                    CategorySettingsView(model: model, category: category, appLanguage: appLanguage)
                        .onAppear {
                            print("🟡 CategoryDetailView: Showing CategorySettingsView for category: \(category.rawValue)")
                        }
                } else {
                    Text("Error: No category selected")
                        .foregroundColor(.red)
                        .padding()
                        .onAppear {
                            print("🔴 CategoryDetailView: category is nil, cannot show settings")
                        }
                }
            }
        }
        // .navigationViewStyle(.stack) - NavigationStack is stack by default
        .onAppear {
            print("🟢 CategoryDetailView body appeared, category: \(category?.rawValue ?? "nil"), outerWorldSteps: \(outerWorldSteps)")
        }
    }
    
    private var categoryTitle: String {
        switch category {
        case .activity: return loc(appLanguage, "Activity")
        case .creativity: return loc(appLanguage, "Creativity")
        case .joys: return loc(appLanguage, "Joys")
        case nil: return loc(appLanguage, "Outer World")
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(categoryColor.opacity(0.2))
                    .frame(width: 80, height: 80)
                
                Image(systemName: categoryIcon)
                    .font(.notoSerif(36, weight: .semibold))
                    .foregroundColor(categoryColor)
            }
            
            // Points
            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(currentPoints)")
                        .font(.notoSerif(48, weight: .bold))
                        .foregroundColor(.primary)
                        .monospacedDigit()
                    Text("/\(maxPoints)")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                Text(loc(appLanguage, "points"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 20)
    }
    
    @ViewBuilder
    private func categoryContent(category: EnergyCategory) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Steps/Sleep info
            if category == .activity {
                stepsInfoSection
            } else if category == .joys {
                sleepInfoSection
            }
            
            // Options list
            optionsSection(category: category)
        }
    }
    
    private var outerWorldContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(loc(appLanguage, "Collect energy drops from the map by exploring the Outer World"))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            
            Text(loc(appLanguage, "Daily cap: 50 energy"))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var stepsInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(loc(appLanguage, "Steps"))
                .font(.headline)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(formatNumber(Int(model.stepsToday)))")
                        .font(.title2.bold())
                    Text(loc(appLanguage, "steps today"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(model.stepsPointsToday)/\(EnergyDefaults.stepsMaxPoints)")
                        .font(.title3.bold())
                    Text(loc(appLanguage, "points"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    private var sleepInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(loc(appLanguage, "Sleep"))
                .font(.headline)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(format: "%.1fh", model.dailySleepHours))
                        .font(.title2.bold())
                    Text(loc(appLanguage, "hours slept"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(model.sleepPointsToday)/\(EnergyDefaults.sleepMaxPoints)")
                        .font(.title3.bold())
                    Text(loc(appLanguage, "points"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    @ViewBuilder
    private func optionsSection(category: EnergyCategory) -> some View {
        let options = model.preferredOptions(for: category)
        
        VStack(alignment: .leading, spacing: 16) {
            Text(loc(appLanguage, "Activities"))
                .font(.headline)
            
            if options.isEmpty {
                Text(loc(appLanguage, "No activities selected. Tap Edit to add activities."))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(options) { option in
                        optionRow(option: option, category: category)
                    }
                }
            }
        }
    }
    
    private func optionRow(option: EnergyOption, category: EnergyCategory) -> some View {
        let isSelected = model.isDailySelected(option.id, category: category)
        
        return Button {
            withAnimation(.spring(response: 0.3)) {
                model.toggleDailySelection(optionId: option.id, category: category)
            }
        } label: {
            HStack(spacing: 12) {
                // Checkbox
                ZStack {
                    Circle()
                        .fill(isSelected ? categoryColor : Color(.systemGray5))
                        .frame(width: 24, height: 24)
                    
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.notoSerif(12, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                
                // Title
                Text(option.title(for: appLanguage))
                    .font(.subheadline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Points badge
                Text("+\(EnergyDefaults.selectionPoints)")
                    .font(.caption.weight(.bold))
                    .foregroundColor(isSelected ? categoryColor : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(isSelected ? categoryColor.opacity(0.15) : Color(.systemGray5))
                    )
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? categoryColor.opacity(0.1) : Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? categoryColor.opacity(0.3) : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    private var editButton: some View {
        Button {
            showSettings = true
        } label: {
            HStack {
                Image(systemName: "gearshape.fill")
                Text(loc(appLanguage, "Edit"))
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                LinearGradient(
                    colors: [categoryColor, categoryColor.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: categoryColor.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .accessibilityIdentifier("category_edit_button")
        .padding(.top, 20)
    }
    
    // Computed properties
    private var categoryColor: Color {
        switch category {
        case .activity: return .green
        case .creativity: return .purple
        case .joys: return .orange
        case nil: return .cyan
        }
    }
    
    private var categoryIcon: String {
        switch category {
        case .activity: return "figure.run"
        case .creativity: return "sparkles"
        case .joys: return "heart.fill"
        case nil: return "battery.100.bolt"
        }
    }
    
    private var currentPoints: Int {
        switch category {
        case .activity: return model.activityPointsToday
        case .creativity: return model.creativityPointsToday
        case .joys: return model.joysCategoryPointsToday
        case nil: return outerWorldSteps
        }
    }
    
    private var maxPoints: Int {
        switch category {
        case .activity: return 40
        case .creativity: return 20
        case .joys: return 40
        case nil: return 50
        }
    }
    
    private func formatNumber(_ value: Int) -> String {
        value < 1000 ? "\(value)" : "\(value / 1000)k"
    }
}
