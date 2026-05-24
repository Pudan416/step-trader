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
    @FocusState private var isLabelFocused: Bool

    private var canAdd: Bool {
        !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
            .padding(.bottom, 20)

            // Category picker
            HStack(spacing: 10) {
                ForEach(EnergyCategory.allCases) { category in
                    MomentCategoryButton(
                        category: category,
                        isSelected: selectedCategory == category,
                        onTap: {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                selectedCategory = category
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)

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
        .onAppear { isLabelFocused = true }
    }

    // MARK: - Commit

    private func commit() {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        model.addMoment(label: trimmed, icon: "sparkles", category: selectedCategory)
        dismiss()
    }
}

// MARK: - Category Button

private struct MomentCategoryButton: View {
    let category: EnergyCategory
    let isSelected: Bool
    let onTap: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Image(systemName: category.iconName)
                    .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? category.color : theme.adaptiveSecondaryText)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(isSelected ? category.color.opacity(0.15) : Color.primary.opacity(0.05))
                    )
                Text(category.displayName)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? category.color : theme.adaptiveSecondaryText)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(category.displayName) category", comment: "MomentEntry – category VoiceOver label"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Preview

#Preview {
    MomentEntrySheet(model: DIContainer.shared.makeAppModel())
        .preferredColorScheme(.dark)
}
