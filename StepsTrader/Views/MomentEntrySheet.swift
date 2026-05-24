import SwiftUI

// MARK: - Moment Entry Sheet
//
// A compact sheet for logging a one-time life event (EphemeralMoment).
// User types a label and picks a category — that's all.
// The moment is stored only in today's snapshot, not in the activity library.

struct MomentEntrySheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

    @State private var label: String = ""
    @State private var selectedCategory: EnergyCategory = .heart
    /// Set when the user taps a full category; auto-clears after a few seconds.
    @State private var fullCategoryWarning: EnergyCategory? = nil
    @State private var warningDismissTask: Task<Void, Never>? = nil
    /// Trigger for the "category is full" warning haptic.
    @State private var warningHapticTick = 0
    @FocusState private var isLabelFocused: Bool

    private let maxSelections = EnergyDefaults.maxSelectionsPerCategory

    private func selectionsCount(for category: EnergyCategory) -> Int {
        model.dailySelectionsCount(for: category)
    }

    private func isFull(_ category: EnergyCategory) -> Bool {
        selectionsCount(for: category) >= maxSelections
    }

    /// First category that still has room. Used to pick a sensible default on
    /// appear if `.heart` is already full.
    private var firstAvailableCategory: EnergyCategory? {
        EnergyCategory.allCases.first { !isFull($0) }
    }

    private var allCategoriesFull: Bool {
        EnergyCategory.allCases.allSatisfy { isFull($0) }
    }

    private var canAdd: Bool {
        !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !isFull(selectedCategory)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Handle
            RoundedRectangle(cornerRadius: 3)
                .fill(theme.adaptiveSecondaryText.opacity(0.4))
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 20)

            // Title
            Text(String(localized: "Something special today", comment: "MomentEntry – sheet title"))
                .font(.headline)
                .foregroundStyle(theme.textPrimary)
                .padding(.bottom, 6)

            Text(String(localized: "This stays on today's canvas and history — not in your library.", comment: "MomentEntry – subtitle"))
                .font(.caption)
                .foregroundStyle(theme.adaptiveSecondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)

            // Text field
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(selectedCategory.color)
                    .frame(width: 24)

                TextField(
                    String(localized: "Wedding, concert, new job…", comment: "MomentEntry – text field placeholder"),
                    text: $label
                )
                .focused($isLabelFocused)
                .font(.body)
                .foregroundStyle(theme.textPrimary)
                .submitLabel(.done)
                .onSubmit { if canAdd { commit() } }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.primary.opacity(0.06))
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            // Category picker
            HStack(spacing: 10) {
                ForEach(EnergyCategory.allCases) { category in
                    MomentCategoryButton(
                        category: category,
                        count: selectionsCount(for: category),
                        maxCount: maxSelections,
                        isFull: isFull(category),
                        isSelected: selectedCategory == category,
                        onTap: { handleCategoryTap(category) }
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            // Warning slot — reserves a fixed height so toggling it doesn't
            // make the rest of the sheet jump.
            warningArea
                .frame(maxWidth: .infinity, minHeight: 36)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            // Add button
            Button(action: commit) {
                Text(String(localized: "Add Moment", comment: "MomentEntry – confirm button"))
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(canAdd ? selectedCategory.color : Color.primary.opacity(0.15))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canAdd)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            Spacer(minLength: 0)
        }
        // `.medium` resizes naturally with Dynamic Type and respects the
        // safe-area on every device — a fixed height would clip large-text
        // users mid-button.
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .choicesSheetPresentationBackground()
        .presentationCornerRadius(28)
        .sensoryFeedback(.warning, trigger: warningHapticTick)
        .onAppear {
            // If the default selection is already full, hop to the first slot
            // that still has room — otherwise the user opens the sheet with a
            // visibly disabled Add button and no obvious next step.
            if isFull(selectedCategory), let fallback = firstAvailableCategory {
                selectedCategory = fallback
            }
            isLabelFocused = true
        }
        .onDisappear {
            warningDismissTask?.cancel()
        }
    }

    // MARK: - Warning area

    @ViewBuilder
    private var warningArea: some View {
        if allCategoriesFull {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(String(localized: "All categories are full today. Remove an activity or try again tomorrow.", comment: "MomentEntry – all categories full warning"))
                    .font(.caption)
                    .foregroundStyle(theme.adaptiveSecondaryText)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)
        } else if let warningCat = fullCategoryWarning {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(warningCat.color)
                Text(String(localized: "\(warningCat.displayName) is full (\(maxSelections)/\(maxSelections)). Pick another or remove an activity first.", comment: "MomentEntry – full category warning"))
                    .font(.caption)
                    .foregroundStyle(theme.adaptiveSecondaryText)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    // MARK: - Category tap handling

    private func handleCategoryTap(_ category: EnergyCategory) {
        if isFull(category) {
            warningHapticTick &+= 1
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                fullCategoryWarning = category
            }
            scheduleWarningDismiss()
            return
        }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            selectedCategory = category
            fullCategoryWarning = nil
        }
        warningDismissTask?.cancel()
    }

    private func scheduleWarningDismiss() {
        warningDismissTask?.cancel()
        warningDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                fullCategoryWarning = nil
            }
        }
    }

    // MARK: - Commit

    private func commit() {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isFull(selectedCategory) else { return }
        model.addMoment(label: trimmed, icon: "sparkles", category: selectedCategory)
        dismiss()
    }
}

// MARK: - Category Button

private struct MomentCategoryButton: View {
    let category: EnergyCategory
    let count: Int
    let maxCount: Int
    let isFull: Bool
    let isSelected: Bool
    let onTap: () -> Void

    @Environment(\.appTheme) private var theme

    private var iconForeground: Color {
        if isFull { return theme.adaptiveSecondaryText.opacity(0.4) }
        return isSelected ? category.color : theme.adaptiveSecondaryText
    }

    private var circleFill: Color {
        if isFull { return Color.primary.opacity(0.03) }
        return isSelected ? category.color.opacity(0.15) : Color.primary.opacity(0.05)
    }

    private var counterColor: Color {
        if isFull { return .orange }
        return theme.adaptiveSecondaryText.opacity(0.6)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: category.iconName)
                        .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(iconForeground)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(circleFill))

                    if isFull {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(3)
                            .background(Circle().fill(.orange))
                            .offset(x: 2, y: -2)
                    }
                }
                Text(category.displayName)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(iconForeground)

                Text("\(count)/\(maxCount)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(counterColor)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(category.displayName) category", comment: "MomentEntry – category VoiceOver label"))
        .accessibilityValue(Text("\(count) of \(maxCount) used", comment: "MomentEntry – category usage VoiceOver value"))
        .accessibilityHint(isFull
            ? Text("Category is full. Remove an activity first.", comment: "MomentEntry – full category VoiceOver hint")
            : Text(""))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Preview

#Preview {
    MomentEntrySheet(model: DIContainer.shared.makeAppModel())
        .preferredColorScheme(.dark)
}
