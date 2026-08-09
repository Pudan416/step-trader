import SwiftUI

/// Catalog-only creator used by the palette's add control.
///
/// The parent owns catalog persistence and selection replacement; this panel
/// only normalizes a title and sends it through after explicit confirmation.
struct HappeningCreatorPanel: View {
    let onCreate: (String) -> Void
    let onCancel: () -> Void

    @State private var text = ""

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add a happening")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityHint("This will replace one of the 10 shown happenings.")
                    .accessibilitySortPriority(
                        HappeningPanelAccessibilityOrder.priority(
                            for: .heading,
                            in: HappeningPanelAccessibilityOrder.creator
                        )
                    )

                Text("This will replace one of the 10 shown happenings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                HappeningFreeTextField(text: $text) { submittedTitle in
                    onCreate(submittedTitle)
                }
                .accessibilitySortPriority(
                    HappeningPanelAccessibilityOrder.priority(
                        for: .input,
                        in: HappeningPanelAccessibilityOrder.creator
                    )
                )

                HStack {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.bordered)

                    Spacer()

                    Button("Add to palette") {
                        create()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmed.isEmpty)
                }
                .accessibilitySortPriority(
                    HappeningPanelAccessibilityOrder.priority(
                        for: .actions,
                        in: HappeningPanelAccessibilityOrder.creator
                    )
                )
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .frame(maxWidth: 440, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 0.75)
        }
        .shadow(color: .black.opacity(0.24), radius: 24, y: 12)
        .accessibilityElement(children: .contain)
    }

    private func create() {
        guard !trimmed.isEmpty else { return }
        onCreate(trimmed)
    }
}

/// A focused title field shared by the compact creator panel and previews.
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

#Preview("Creator") {
    HappeningCreatorPanel(onCreate: { _ in }, onCancel: {})
        .padding()
        .dynamicTypeSize(.accessibility1)
        .frame(height: 280)
}
