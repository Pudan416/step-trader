import SwiftUI

/// Free-text entry inside the palette's `+` node.
///
/// Submitting creates the happening and spawns its canvas element in the same
/// action: no confirm step, no category, no icon picker. This is what replaces
/// the ✦ Moment sheet.
struct HappeningFreeTextField: View {

    @Binding var text: String
    let onSubmit: (String) -> Void

    @FocusState private var isFocused: Bool

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        TextField(
            String(localized: "What happened?", comment: "Palette free-text placeholder"),
            text: $text
        )
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(.black.opacity(0.8))
        .multilineTextAlignment(.center)
        .textInputAutocapitalization(.sentences)
        // A happening is whatever the user calls it. Autocorrect against the
        // active keyboard language rewrites unfamiliar words outright — typing
        // "Sauna" on a Russian keyboard produced "Выгоды" — and the label is
        // then wrong forever. A typo is the lesser failure.
        .autocorrectionDisabled(true)
        .submitLabel(.done)
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onSubmit {
            // Whitespace-only input is a mis-tap, not a happening.
            guard !trimmed.isEmpty else { return }
            onSubmit(trimmed)
        }
    }
}
