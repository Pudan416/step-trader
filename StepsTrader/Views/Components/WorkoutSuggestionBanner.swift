import SwiftUI

struct ActivitySuggestionBanner: View {
    let suggestions: [ActivitySuggestion]
    let onAccept: (ActivitySuggestion) -> Void
    let onDismiss: (ActivitySuggestion) -> Void
    let onDismissAll: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: 8) {
            ForEach(suggestions.prefix(3)) { suggestion in
                suggestionCard(suggestion)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
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
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private func suggestionCard(_ suggestion: ActivitySuggestion) -> some View {
        HStack(spacing: 12) {
            Image(systemName: suggestion.icon)
                .font(.system(size: 18))
                .foregroundStyle(theme.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(suggestion.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    onAccept(suggestion)
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Text(String(localized: "Add"))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(theme.accentColor, in: Capsule())
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    onDismiss(suggestion)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
