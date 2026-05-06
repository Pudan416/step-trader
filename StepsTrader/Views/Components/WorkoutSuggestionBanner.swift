import SwiftUI

struct ActivitySuggestionBanner: View {
    let suggestions: [ActivitySuggestion]
    let onAccept: (ActivitySuggestion) -> Void
    let onDismiss: (ActivitySuggestion) -> Void
    let onDismissAll: () -> Void

    @Environment(\.appTheme) private var theme

    @State private var isExpanded = false

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

            HStack(spacing: 16) {
                if suggestions.count > 1 && !isExpanded {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isExpanded = true
                        }
                    } label: {
                        Text(String(localized: "+\(suggestions.count - 1) more", comment: "ActivitySuggestionBanner – show more"))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
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
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 60)
        .padding(.top, 8)
    }

    private func suggestionCard(_ suggestion: ActivitySuggestion) -> some View {
        HStack(spacing: 10) {
            Image(systemName: suggestion.icon)
                .font(.title3)
                .foregroundStyle(theme.accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(suggestion.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .layoutPriority(1)

            Spacer(minLength: 4)

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    onAccept(suggestion)
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Text(String(localized: "Add"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(theme.accentColor, in: Capsule())
            }
            .buttonStyle(.plain)
            .fixedSize()

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    onDismiss(suggestion)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Dismiss suggestion", comment: "ActivitySuggestionBanner – dismiss VoiceOver label"))
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 10)
        .glassCard(cornerRadius: 14)
    }
}
