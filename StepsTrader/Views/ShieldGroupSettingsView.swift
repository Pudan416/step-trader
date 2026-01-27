import SwiftUI
#if canImport(FamilyControls)
import FamilyControls
#endif

struct ShieldGroupSettingsView: View {
    @ObservedObject var model: AppModel
    @State var group: AppModel.ShieldGroup
    let appLanguage: String
    @Environment(\.dismiss) private var dismiss
    @State private var showAppPicker = false
    @State private var pickerSelection = FamilyActivitySelection()
    @State private var showAuthAlert = false
    @State private var showIntervals = false
    @State private var isUnlocking = false
    
    // Computed dynamic title based on selection
    private var displayTitle: String {
        let appCount = group.selection.applicationTokens.count
        let catCount = group.selection.categoryTokens.count
        
        if appCount == 1 && catCount == 0 {
            return "App Shield"
        } else if appCount == 0 && catCount == 1 {
            return "Category Shield"
        } else if appCount + catCount == 0 {
            return "New Shield"
        } else {
            return "\(appCount + catCount) Apps Shield"
        }
    }
    
    // Get first enabled interval for quick unlock
    private var quickUnlockIntervals: [AccessWindow] {
        let available: [AccessWindow] = [.minutes5, .minutes15, .minutes30, .hour1]
        return available.filter { group.enabledIntervals.contains($0) }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Quick unlock section at top
                    if !group.selection.applicationTokens.isEmpty || !group.selection.categoryTokens.isEmpty {
                        quickUnlockSection
                    }
                    
                    // Apps in group
                    appsInGroupSection
                    
                    // Difficulty slider with cost preview
                    difficultySection
                    
                    // Intervals (collapsible)
                    intervalsSection
                    
                    // Delete button
                    deleteGroupButton
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.updateShieldGroup(group)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showAppPicker) {
                #if canImport(FamilyControls)
                AppSelectionSheet(
                    selection: $pickerSelection,
                    appLanguage: appLanguage,
                    onDone: {
                        group.selection.applicationTokens.formUnion(pickerSelection.applicationTokens)
                        group.selection.categoryTokens.formUnion(pickerSelection.categoryTokens)
                        showAppPicker = false
                    }
                )
                #endif
            }
            .alert("Authorization Required", isPresented: $showAuthAlert) {
                Button("OK") { }
            } message: {
                Text("Please authorize Family Controls in Settings to enable shield features")
            }
        }
    }
    
    // MARK: - Quick Unlock Section
    private var quickUnlockSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "lock.open.fill")
                    .foregroundColor(.green)
                Text("Quick Unlock")
                    .font(.headline)
                Spacer()
                
                if let remaining = model.remainingUnlockTime(for: group.id) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.caption)
                        Text(formatRemainingTime(remaining))
                            .font(.caption.weight(.medium))
                    }
                    .foregroundColor(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.green.opacity(0.15))
                    .clipShape(Capsule())
                }
            }
            
            if model.isGroupUnlocked(group.id) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Currently unlocked")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
                // Quick unlock buttons
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 10) {
                    ForEach(quickUnlockIntervals.prefix(4), id: \.self) { interval in
                        unlockButton(for: interval)
                    }
                }
            }
        }
        .padding(16)
        .background(glassCard)
    }
    
    private func unlockButton(for interval: AccessWindow) -> some View {
        let cost = group.cost(for: interval)
        let canAfford = model.totalStepsBalance >= cost
        
        return Button {
            Task {
                isUnlocking = true
                await model.handlePayGatePaymentForGroup(
                    groupId: group.id,
                    window: interval,
                    costOverride: cost
                )
                isUnlocking = false
            }
        } label: {
            VStack(spacing: 4) {
                Text(interval.displayName)
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 2) {
                    Image(systemName: "bolt.fill")
                        .font(.caption2)
                    Text("\(cost)")
                        .font(.caption.weight(.medium))
                }
                .foregroundColor(canAfford ? .green : .red)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(canAfford ? Color.green.opacity(0.1) : Color.gray.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(canAfford ? Color.green.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .disabled(!canAfford || isUnlocking)
        .buttonStyle(.plain)
    }
    
    // MARK: - Apps in Group Section
    private var appsInGroupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "app.badge.fill")
                    .foregroundColor(.blue)
                Text("Protected Apps")
                    .font(.headline)
                Spacer()
                Text("\(group.selection.applicationTokens.count + group.selection.categoryTokens.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            
            if group.selection.applicationTokens.isEmpty && group.selection.categoryTokens.isEmpty {
                Button {
                    pickerSelection = FamilyActivitySelection()
                    showAppPicker = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                        Text("Add Apps")
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 8) {
                    #if canImport(FamilyControls)
                    ForEach(Array(group.selection.applicationTokens.enumerated()), id: \.offset) { index, token in
                        appRow(token: token, isCategory: false)
                            .id("app_\(index)")
                    }
                    ForEach(Array(group.selection.categoryTokens.enumerated()), id: \.offset) { index, token in
                        appRow(token: token, isCategory: true)
                            .id("cat_\(index)")
                    }
                    #endif
                    
                    Button {
                        pickerSelection = group.selection
                        showAppPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle")
                                .foregroundColor(.blue)
                            Text("Add More")
                                .foregroundColor(.blue)
                        }
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(glassCard)
    }
    
    @ViewBuilder
    private func appRow(token: Any, isCategory: Bool) -> some View {
        #if canImport(FamilyControls)
        if isCategory, let catToken = token as? ActivityCategoryToken {
            HStack {
                Label(catToken)
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline)
                
                Spacer()
                
                Button {
                    group.selection.categoryTokens.remove(catToken)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 6)
        } else if let appToken = token as? ApplicationToken {
            HStack {
                Label(appToken)
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline)
                
                Spacer()
                
                Button {
                    group.selection.applicationTokens.remove(appToken)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 6)
        }
        #endif
    }
    
    // MARK: - Difficulty Section with Slider
    private var difficultySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "dial.high.fill")
                    .foregroundColor(difficultyColor(for: group.difficultyLevel))
                Text("Difficulty")
                    .font(.headline)
                Spacer()
                Text(difficultyLabel)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(difficultyColor(for: group.difficultyLevel))
            }
            
            // Slider
            VStack(spacing: 8) {
                Slider(
                    value: Binding(
                        get: { Double(group.difficultyLevel) },
                        set: { group.difficultyLevel = Int($0.rounded()) }
                    ),
                    in: 1...5,
                    step: 1
                )
                .tint(difficultyColor(for: group.difficultyLevel))
                
                // Level indicators
                HStack {
                    ForEach(1...5, id: \.self) { level in
                        Text("\(level)")
                            .font(.caption2.weight(level == group.difficultyLevel ? .bold : .regular))
                            .foregroundColor(level == group.difficultyLevel ? difficultyColor(for: level) : .secondary)
                        if level < 5 { Spacer() }
                    }
                }
                .padding(.horizontal, 4)
            }
            
            // Cost preview
            costPreviewGrid
        }
        .padding(16)
        .background(glassCard)
    }
    
    private var difficultyLabel: String {
        switch group.difficultyLevel {
        case 1: return "Very Easy"
        case 2: return "Easy"
        case 3: return "Medium"
        case 4: return "Hard"
        case 5: return "Very Hard"
        default: return "Medium"
        }
    }
    
    private var costPreviewGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Energy cost per interval")
                .font(.caption)
                .foregroundColor(.secondary)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach([AccessWindow.minutes5, .minutes15, .minutes30, .hour1, .hour2], id: \.self) { interval in
                    if group.enabledIntervals.contains(interval) {
                        costPreviewItem(interval: interval)
                    }
                }
            }
        }
    }
    
    private func costPreviewItem(interval: AccessWindow) -> some View {
        VStack(spacing: 2) {
            Text(interval.displayName)
                .font(.caption2)
                .foregroundColor(.secondary)
            HStack(spacing: 2) {
                Image(systemName: "bolt.fill")
                    .font(.caption2)
                Text("\(group.cost(for: interval))")
                    .font(.caption.weight(.semibold))
            }
            .foregroundColor(difficultyColor(for: group.difficultyLevel))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(difficultyColor(for: group.difficultyLevel).opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - Intervals Section (Collapsible)
    private var intervalsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showIntervals.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "clock.fill")
                        .foregroundColor(.orange)
                    Text("Time Intervals")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    
                    Text("\(group.enabledIntervals.count) enabled")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(showIntervals ? 90 : 0))
                }
            }
            .buttonStyle(.plain)
            
            if showIntervals {
                VStack(spacing: 8) {
                    ForEach([AccessWindow.minutes5, .minutes15, .minutes30, .hour1, .hour2], id: \.self) { interval in
                        intervalToggleRow(interval: interval)
                    }
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(glassCard)
    }
    
    private func intervalToggleRow(interval: AccessWindow) -> some View {
        HStack {
            Toggle(isOn: Binding(
                get: { group.enabledIntervals.contains(interval) },
                set: { enabled in
                    if enabled {
                        group.enabledIntervals.insert(interval)
                    } else {
                        // Don't allow disabling all intervals
                        if group.enabledIntervals.count > 1 {
                            group.enabledIntervals.remove(interval)
                        }
                    }
                }
            )) {
                HStack {
                    Text(interval.displayName)
                        .font(.subheadline)
                    Spacer()
                    HStack(spacing: 2) {
                        Image(systemName: "bolt.fill")
                            .font(.caption2)
                        Text("\(group.cost(for: interval))")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
            }
            .tint(.green)
        }
    }
    
    // MARK: - Delete Button
    private var deleteGroupButton: some View {
        Button {
            model.deleteShieldGroup(group.id)
            dismiss()
        } label: {
            HStack {
                Image(systemName: "trash")
                Text("Remove Shield")
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundColor(.red)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Helpers
    private func difficultyColor(for level: Int) -> Color {
        switch level {
        case 1: return .green
        case 2: return .blue
        case 3: return .orange
        case 4: return .red
        case 5: return .purple
        default: return .gray
        }
    }
    
    private func formatRemainingTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if mins >= 60 {
            let hours = mins / 60
            let remainingMins = mins % 60
            return "\(hours)h \(remainingMins)m"
        }
        return "\(mins):\(String(format: "%02d", secs))"
    }
    
    private var glassCard: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
}
