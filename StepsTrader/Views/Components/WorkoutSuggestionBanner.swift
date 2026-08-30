import SwiftUI

/// A two-layer queue of HealthKit and behavioral suggestions.
///
/// Only the front capsule is actionable. The next suggestion stays visible as
/// a quieter glass layer behind it; accepting or dismissing the front advances
/// the queue without turning the canvas into a list of cards.
struct ActivitySuggestionBanner: View {
    let suggestions: [ActivitySuggestion]
    let onAccept: (ActivitySuggestion) -> Void
    let onDismiss: (ActivitySuggestion) -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var acceptHapticTick = 0

    private let backLayerOffset: CGFloat = 14
    private let backLayerScale: CGFloat = 0.94

    var body: some View {
        ZStack(alignment: .bottom) {
            if suggestions.count > 1 {
                depthCapsule(suggestions[1])
                    .scaleEffect(backLayerScale, anchor: .bottom)
                    .offset(y: -backLayerOffset)
                    .zIndex(0)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottom)))
            }

            if let first = suggestions.first {
                suggestionCapsule(first)
                    .zIndex(1)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.96, anchor: .bottom).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            }
        }
        .padding(.top, suggestions.count > 1 ? backLayerOffset : 0)
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.16)
                : .spring(response: 0.34, dampingFraction: 0.82),
            value: suggestions.map(\.id)
        )
        .sensoryFeedback(.impact(weight: .light), trigger: acceptHapticTick)
    }

    private func depthCapsule(_ suggestion: ActivitySuggestion) -> some View {
        Capsule(style: .continuous)
            .fill(.clear)
            .frame(maxWidth: .infinity, minHeight: 66, maxHeight: 66)
            .liquidGlassControl(in: Capsule(style: .continuous), tint: .off)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                String(
                    localized: "Next suggestion: \(suggestion.title)",
                    comment: "ActivitySuggestionBanner – queued suggestion VoiceOver label"
                )
            )
            .accessibilityIdentifier("canvas_activity_suggestion_back")
    }

    private func suggestionCapsule(_ suggestion: ActivitySuggestion) -> some View {
        HStack(spacing: 10) {
            Image(systemName: suggestion.icon)
                .font(.geist(17, weight: .semibold, relativeTo: .body))
                .foregroundStyle(theme.accentColor)
                .frame(width: 38, height: 38)
                .background(theme.accentColor.opacity(0.13), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(suggestion.title)
                    .font(.geist(14, weight: .semibold, relativeTo: .subheadline))
                    .foregroundStyle(.primary)

                Text(suggestion.subtitle)
                    .font(.geist(12, relativeTo: .caption))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .layoutPriority(1)

            Spacer(minLength: 0)

            Button {
                withAnimation(reduceMotion ? .easeOut(duration: 0.16) : .spring(response: 0.32, dampingFraction: 0.8)) {
                    onAccept(suggestion)
                }
                acceptHapticTick &+= 1
            } label: {
                Text(String(localized: "Add"))
                    .font(.geist(13, weight: .semibold, relativeTo: .subheadline))
                    .foregroundStyle(theme.accentColor)
                    .padding(.horizontal, 15)
                    .frame(minHeight: 44)
                    .liquidGlassControl(in: Capsule(style: .continuous), tint: .off)
                    .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: false)

            Button {
                withAnimation(reduceMotion ? .easeOut(duration: 0.16) : .spring(response: 0.3, dampingFraction: 0.82)) {
                    onDismiss(suggestion)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.geist(12, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                String(localized: "Dismiss suggestion", comment: "ActivitySuggestionBanner – dismiss VoiceOver label")
            )
        }
        .padding(.leading, 10)
        .padding(.trailing, 7)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 66)
        .liquidGlassControl(in: Capsule(style: .continuous))
        .contentShape(Capsule(style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("canvas_activity_suggestion_front")
    }
}
