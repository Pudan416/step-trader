import SwiftUI

struct ActivitySuggestionBanner: View {
    let suggestions: [ActivitySuggestion]
    let onAccept: (ActivitySuggestion) -> Void
    let onDismiss: (ActivitySuggestion) -> Void
    let onDismissAll: () -> Void

    @Environment(\.appTheme) private var theme

    @State private var isExpanded = false
    @State private var acceptHapticTick = 0

    var body: some View {
        VStack(spacing: 8) {
            if let first = suggestions.first {
                suggestionCard(first)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            }

            if isExpanded {
                ForEach(suggestions.dropFirst().prefix(2)) { suggestion in
                    suggestionCard(suggestion)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                }
            }

            HStack(spacing: 8) {
                if suggestions.count > 1 && !isExpanded {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isExpanded = true
                        }
                    } label: {
                        Text(String(localized: "+\(suggestions.count - 1) more", comment: "ActivitySuggestionBanner – show more"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .liquidGlassControl(in: Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                if suggestions.count > 1 {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            onDismissAll()
                        }
                    } label: {
                        Text(String(localized: "Dismiss all"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .liquidGlassControl(in: Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 8)
        .sensoryFeedback(.impact(weight: .light), trigger: acceptHapticTick)
    }

    private func suggestionCard(_ suggestion: ActivitySuggestion) -> some View {
        HStack(spacing: 10) {
            Image(systemName: suggestion.icon)
                .font(.system(size: 18))
                .foregroundStyle(theme.accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(suggestion.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .layoutPriority(1)

            Spacer(minLength: 4)

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    onAccept(suggestion)
                }
                acceptHapticTick &+= 1
            } label: {
                Text(String(localized: "Add"))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.accentColor)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .liquidGlassControl(in: Capsule(style: .continuous))
                    .contentShape(Capsule().scale(1.3))
            }
            .buttonStyle(.plain)
            .fixedSize()

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    onDismiss(suggestion)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .liquidGlassControl(in: Circle())
                    .contentShape(Circle().scale(1.4))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Dismiss suggestion", comment: "ActivitySuggestionBanner – dismiss VoiceOver label"))
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
        .glassCard(cornerRadius: 14, style: .lens)
    }
}
