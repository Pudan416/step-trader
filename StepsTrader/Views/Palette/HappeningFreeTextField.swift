import SwiftUI

enum HappeningCreatorActionAppearance {
    static let disabledForegroundOpacity = 1.0
    static let increasedContrastStrokeOpacity = 0.68
}

/// Catalog-only creator used by the palette's add control.
///
/// The parent owns catalog persistence and selection replacement; this panel
/// only normalizes a title and sends it through after explicit confirmation.
struct HappeningCreatorPanel: View {
    let onCreate: (String) -> Void
    let onCancel: () -> Void

    @State private var text = ""
    @FocusState private var isTextFieldFocused: Bool
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var effectiveColorSchemeContrast: ColorSchemeContrast {
        Task7UITestAccessibilityConfiguration.current.usesIncreasedContrast
            ? .increased
            : colorSchemeContrast
    }

    private var usesExpandedActionLayout: Bool {
        HappeningLiquidLayout.usesExpandedLayout(for: dynamicTypeSize)
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
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)

                HappeningFreeTextField(
                    text: $text,
                    isFocused: $isTextFieldFocused
                ) { submittedTitle in
                    onCreate(submittedTitle)
                }
                .accessibilitySortPriority(
                    HappeningPanelAccessibilityOrder.priority(
                        for: .input,
                        in: HappeningPanelAccessibilityOrder.creator
                    )
                )

                Group {
                    if usesExpandedActionLayout {
                        VStack(spacing: 10) {
                            cancelAction
                            addAction
                        }
                    } else {
                        HStack {
                            cancelAction
                            Spacer()
                            addAction
                        }
                    }
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
        .scrollBounceBehavior(.always)
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onChanged { value in
                    guard value.translation.height > 12 else { return }
                    isTextFieldFocused = false
                }
        )
        .accessibilityIdentifier("happening_creator_scroll")
        .frame(maxHeight: usesExpandedActionLayout ? 380 : 320)
        .frame(maxWidth: 440, alignment: .leading)
        .background(
            Color(uiColor: .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
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

    private var cancelAction: some View {
        Button(action: onCancel) {
            Text("Cancel")
                .frame(
                    maxWidth: usesExpandedActionLayout ? .infinity : nil,
                    minHeight: usesExpandedActionLayout ? 44 : nil
                )
        }
        .buttonStyle(.bordered)
    }

    private var addAction: some View {
        Button {
            create()
        } label: {
            Text("Add to palette")
                .font(.body.weight(.semibold))
                .foregroundStyle(
                    trimmed.isEmpty
                        ? Color.primary.opacity(
                            HappeningCreatorActionAppearance.disabledForegroundOpacity
                        )
                        : Color.white
                )
                .padding(.horizontal, 16)
                .frame(
                    maxWidth: usesExpandedActionLayout ? .infinity : nil,
                    minHeight: 44
                )
                .background(
                    trimmed.isEmpty
                        ? Color.primary.opacity(
                            effectiveColorSchemeContrast == .increased ? 0.18 : 0.10
                        )
                        : Color.accentColor,
                    in: Capsule()
                )
                .overlay {
                    Capsule().strokeBorder(
                        Color.primary.opacity(
                            trimmed.isEmpty
                                ? effectiveColorSchemeContrast == .increased
                                    ? HappeningCreatorActionAppearance.increasedContrastStrokeOpacity
                                    : 0.24
                                : 0
                        ),
                        lineWidth: effectiveColorSchemeContrast == .increased ? 1.5 : 1
                    )
                }
        }
        .buttonStyle(.plain)
        .disabled(trimmed.isEmpty)
    }
}

/// A focused title field shared by the compact creator panel and previews.
struct HappeningFreeTextField: View {

    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    let onSubmit: (String) -> Void

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        TextField(
            String(localized: "What happened?", comment: "Palette free-text placeholder"),
            text: $text,
            prompt: Text(
                String(localized: "What happened?", comment: "Palette free-text placeholder")
            )
            .foregroundStyle(.secondary)
        )
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(.primary)
        .multilineTextAlignment(.center)
        .happeningPanelTextFieldStyle()
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
