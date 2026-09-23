import SwiftUI

/// A compact queue above the Canvas controls, using the same readable pigment
/// colors. Only the front card is actionable; the inset edge previews the queue.
struct ActivitySuggestionBanner: View {
    let suggestions: [ActivitySuggestion]
    let onAccept: (ActivitySuggestion) -> Void
    let onDismiss: (ActivitySuggestion) -> Void

    @Environment(\.canvasChromePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var acceptHapticTick = 0

    private let backLayerOffset: CGFloat = 10
    private let cardShape = RoundedRectangle(cornerRadius: 24, style: .continuous)

    var body: some View {
        Group {
            if let first = suggestions.first {
                suggestionCard(first)
                    .background {
                        if suggestions.count > 1 {
                            depthCard(suggestions[1])
                                .padding(.horizontal, 10)
                                .offset(y: -backLayerOffset)
                                .transition(.opacity)
                        }
                    }
                    .id(first.id)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .scale(scale: 0.96, anchor: .bottom).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            }
        }
        .padding(.top, suggestions.count > 1 ? backLayerOffset : 0)
        .frame(maxWidth: 560)
        .animation(queueAnimation, value: suggestions.map(\.id))
        .sensoryFeedback(.impact(weight: .light), trigger: acceptHapticTick)
    }

    private var queueAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.16) : .spring(response: 0.34, dampingFraction: 0.82)
    }

    private func depthCard(_ suggestion: ActivitySuggestion) -> some View {
        // Match the front card's measured height, including wrapped copy and
        // Dynamic Type, so the queue edge always stays just above its top.
        cardShape.fill(palette.earnedColor)
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

    private func suggestionCard(_ suggestion: ActivitySuggestion) -> some View {
        Group {
            if dynamicTypeSize >= .xxxLarge {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 8) {
                        suggestionText(suggestion)
                        dismissButton(suggestion)
                    }
                    acceptButton(suggestion, fullWidth: true)
                }
            } else {
                HStack(spacing: 8) {
                    suggestionText(suggestion)
                    acceptButton(suggestion)
                    dismissButton(suggestion)
                }
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 76)
        .background(palette.surfaceColor, in: cardShape)
        .contentShape(cardShape)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("canvas_activity_suggestion_front")
    }

    private func suggestionText(_ suggestion: ActivitySuggestion) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: suggestion.icon)
                    .font(.geist(16, weight: .medium, relativeTo: .headline))
                    .foregroundStyle(palette.accentColor)
                    .accessibilityHidden(true)
                Text(suggestion.title)
                    .font(.geist(15, weight: .semibold, relativeTo: .headline))
                    .foregroundStyle(palette.textColor)
            }
            Text(suggestion.subtitle)
                .font(.geist(13, relativeTo: .subheadline))
                .foregroundStyle(palette.secondaryColor)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func acceptButton(_ suggestion: ActivitySuggestion, fullWidth: Bool = false) -> some View {
        Button {
            withAnimation(queueAnimation) { onAccept(suggestion) }
            acceptHapticTick &+= 1
        } label: {
            Text(String(localized: "Add"))
                .font(.geist(14, weight: .semibold, relativeTo: .body))
                .foregroundStyle(palette.onAccentColor)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 44)
                .background(palette.accentColor, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: !fullWidth, vertical: false)
        .accessibilityIdentifier("canvas_activity_suggestion_add")
    }

    private func dismissButton(_ suggestion: ActivitySuggestion) -> some View {
        Button {
            withAnimation(queueAnimation) { onDismiss(suggestion) }
        } label: {
            Image(systemName: "xmark")
                .font(.geist(14, weight: .medium, relativeTo: .body))
                .foregroundStyle(palette.secondaryColor)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            String(localized: "Dismiss suggestion", comment: "ActivitySuggestionBanner – dismiss VoiceOver label")
        )
        .accessibilityIdentifier("canvas_activity_suggestion_dismiss")
    }
}


/// One question with quick answers; choosing an answer logs the real happening.
struct EveningReflectionCard: View {
    let date: Date
    let titleForHappening: (String) -> String
    let onChoose: (String) -> Void
    let onChooseOther: () -> Void
    let onDismiss: () -> Void

    @Environment(\.canvasChromePalette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var prompt: (question: String, ids: [String]) {
        switch EveningReflection.questionIndex(for: date) {
        case 0:
            (String(localized: "What would you like to keep from today?"),
             ["happening_called_someone", "happening_laughed", "happening_made_something"])
        case 1:
            (String(localized: "Was there a moment just for you?"),
             ["happening_read", "happening_outside", "happening_did_nothing"])
        default:
            (String(localized: "What made today feel different?"),
             ["happening_walk", "happening_drinks", "happening_made_something"])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Text(prompt.question)
                    .font(.geist(18, weight: .medium, relativeTo: .headline))
                    .foregroundStyle(palette.textColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("canvas_evening_reflection_question")
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.geist(14, weight: .medium, relativeTo: .body))
                        .foregroundStyle(palette.secondaryColor)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Dismiss suggestion"))
                .accessibilityIdentifier("canvas_evening_reflection_dismiss")
            }
            if dynamicTypeSize.isAccessibilitySize {
                verticalChoices
            } else {
                FlowLayout(spacing: 8) { choices }
            }
            Button(action: onChooseOther) {
                Text(String(localized: "Choose something else"))
                    .font(.geist(14, weight: .medium, relativeTo: .subheadline))
                    .foregroundStyle(palette.secondaryColor)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("canvas_evening_reflection_other")
        }
        .padding(16)
        .frame(maxWidth: 560, alignment: .leading)
        .background(palette.surfaceColor, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("canvas_evening_reflection")
    }

    private var verticalChoices: some View {
        VStack(alignment: .leading, spacing: 8) { choices }
    }

    private var choices: some View {
        ForEach(prompt.ids, id: \.self) { id in
            Button { onChoose(id) } label: {
                Text(titleForHappening(id))
                    .font(.geist(14, weight: .medium, relativeTo: .body))
                    .foregroundStyle(palette.textColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(minHeight: 44)
                    .background(palette.trackColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("canvas_evening_choice_" + id)
        }
    }
}
