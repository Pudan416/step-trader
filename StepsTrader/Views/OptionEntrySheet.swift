import SwiftUI

struct OptionEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

    let option: EnergyOption
    let category: EnergyCategory
    @Binding var entry: OptionEntry?
    let onSave: (OptionEntry) -> Void

    @State private var selectedColorHex: String = CanvasColorPalette.paletteHex[0]
    @State private var text: String = ""
    @FocusState private var isTextFieldFocused: Bool

    private var examples: [String] {
        let raw = EnergyDefaults.optionDescriptions[option.id]?.examples ?? ""
        return raw.components(separatedBy: ", ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Asset names for the current category
    private var categoryAssets: [String] {
        switch category {
        case .body: return ["body 1", "body 2", "body 3"]
        case .mind: return ["mind 1"]
        case .heart: return ["heart 1"]
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Activity title
                    Text(option.title(for: "en"))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.textPrimary)

                    // Examples — small inline list
                    if !examples.isEmpty {
                        examplesSection
                    }

                    // Personal note (optional)
                    noteSection

                    // Color asset grid — category assets tinted with palette colors
                    colorAssetGrid

                    // Save
                    saveButton
                }
                .padding(20)
                .padding(.bottom, 20)
            }
            .scrollContentBackground(.hidden)
            .background(.ultraThinMaterial)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 15, weight: .medium))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            if let entry = entry {
                selectedColorHex = entry.colorHex
                text = entry.text
            } else {
                selectedColorHex = defaultColorHex
            }
        }
    }

    // MARK: - Examples

    private var examplesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("e.g.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.textSecondary.opacity(0.5))
                .textCase(.uppercase)

            FlowLayout(spacing: 6) {
                ForEach(examples, id: \.self) { example in
                    Text(example)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(theme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(theme.textPrimary.opacity(0.05))
                        )
                }
            }
        }
    }

    // MARK: - Note

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Note")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.textSecondary.opacity(0.6))
                Text("optional")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(theme.textSecondary.opacity(0.3))
                Spacer()
                if !text.isEmpty {
                    Text("\(text.count)/200")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.textSecondary.opacity(0.4))
                }
            }

            TextField("", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .padding(12)
                .lineLimit(2...5)
                .frame(minHeight: 60)
                .focused($isTextFieldFocused)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(theme.textPrimary.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isTextFieldFocused ? Color(hex: selectedColorHex).opacity(0.3) : Color.clear, lineWidth: 1)
                        )
                )
                .onChange(of: text) { _, newValue in
                    if newValue.count > 200 {
                        text = String(newValue.prefix(200))
                    }
                }
        }
    }

    // MARK: - Color Asset Grid

    /// Shows category assets tinted in each palette color. Tap to select color.
    private var colorAssetGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Color")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.textSecondary.opacity(0.6))

            let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(CanvasColorPalette.paletteHex.enumerated()), id: \.offset) { index, hex in
                    let assetName = categoryAssets[index % categoryAssets.count]
                    let isSelected = hex == selectedColorHex

                    Button {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                            selectedColorHex = hex
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        ZStack {
                            // Tinted asset
                            if let uiImage = UIImage(named: assetName)?.withRenderingMode(.alwaysTemplate) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .foregroundStyle(Color(hex: hex))
                                    .frame(width: 44, height: 44)
                            } else {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 36, height: 36)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(hex: hex).opacity(isSelected ? 0.15 : 0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isSelected ? Color(hex: hex).opacity(0.5) : Color.clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Save

    private var saveButton: some View {
        Button {
            saveEntry()
        } label: {
            Text("Add to canvas")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(hex: selectedColorHex))
                )
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    // MARK: - Helpers

    private var defaultColorHex: String {
        switch category {
        case .body:  return "#C3143B"
        case .mind:  return "#7652AF"
        case .heart: return "#FEAAC2"
        }
    }

    private func saveEntry() {
        let dayKey = AppModel.dayKey(for: Date())
        let newEntry = OptionEntry(
            id: "\(option.id)_\(dayKey)",
            dayKey: dayKey,
            optionId: option.id,
            category: category,
            colorHex: selectedColorHex,
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            timestamp: Date()
        )
        onSave(newEntry)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

#Preview {
    @Previewable @State var entry: OptionEntry? = nil

    OptionEntrySheet(
        option: EnergyOption(
            id: "body_walking",
            titleEn: "Walking",
            titleRu: "Ходьба",
            category: .body,
            icon: "figure.walk"
        ),
        category: .body,
        entry: $entry,
        onSave: { _ in }
    )
}
