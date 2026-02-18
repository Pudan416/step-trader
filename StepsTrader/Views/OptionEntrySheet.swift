import SwiftUI

struct OptionEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

    let option: EnergyOption
    let category: EnergyCategory
    @Binding var entry: OptionEntry?
    let onSave: (OptionEntry) -> Void

    @State private var selectedColorHex: String = CanvasColorPalette.paletteHex[0]
    @State private var selectedAssetVariant: Int = Int.random(in: 0...2)
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
                            .foregroundStyle(.primary)

                        // Examples — small inline list
                        if !examples.isEmpty {
                            examplesSection
                        }

                        // Personal note (optional)
                        noteSection

                        // Shape picker — body only
                        if category == .body {
                            shapePickerSection
                        }

                        // Color asset grid — category assets tinted with palette colors
                        colorAssetGrid
                    }
                    .padding(20)
                    .padding(.bottom, 20)
                }
            .scrollContentBackground(.hidden)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary.opacity(0.8))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        saveEntry()
                    } label: {
                        Text("Add")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(Color(hex: selectedColorHex))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
        .onAppear {
            if let entry = entry {
                selectedColorHex = entry.colorHex
                text = entry.text
                if let variant = entry.assetVariant {
                    selectedAssetVariant = variant
                }
            } else {
                selectedColorHex = category.defaultColorHex
                if category == .body {
                    selectedAssetVariant = Int.random(in: 0...2)
                }
            }
        }
    }

    // MARK: - Examples

    private var examplesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("e.g.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary.opacity(0.6))
                .textCase(.uppercase)

            FlowLayout(spacing: 6) {
                ForEach(examples, id: \.self) { example in
                    Button {
                        if text.isEmpty {
                            text = example
                        } else {
                            text += ", \(example)"
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Text(example)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(Color.primary.opacity(0.05))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .glassCard()
    }

    // MARK: - Note

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Note")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.6))
                Text("optional")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.secondary.opacity(0.3))
                Spacer()
                if !text.isEmpty {
                    Text("\(text.count)/200")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary.opacity(0.4))
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
                        .fill(Color.primary.opacity(0.04))
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
        .padding(14)
        .glassCard()
    }

    // MARK: - Shape Picker (Body only)

    private let shapeLabels = ["Circle", "Square", "Triangle"]
    private let shapeIcons = ["circle.fill", "square.fill", "triangle.fill"]

    private var shapePickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Shape")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary.opacity(0.6))

            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { index in
                    let isSelected = index == selectedAssetVariant
                    let assetName = categoryAssets[index]

                    Button {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                            selectedAssetVariant = index
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        VStack(spacing: 6) {
                            if let uiImage = UIImage(named: assetName)?.withRenderingMode(.alwaysTemplate) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .foregroundStyle(Color(hex: selectedColorHex).opacity(isSelected ? 1.0 : 0.4))
                                    .frame(width: 40, height: 40)
                            } else {
                                Image(systemName: shapeIcons[index])
                                    .font(.system(size: 28))
                                    .foregroundStyle(Color(hex: selectedColorHex).opacity(isSelected ? 1.0 : 0.4))
                            }

                            Text(shapeLabels[index])
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary.opacity(isSelected ? 1.0 : 0.5))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(hex: selectedColorHex).opacity(isSelected ? 0.12 : 0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isSelected ? Color(hex: selectedColorHex).opacity(0.5) : Color.clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .glassCard()
    }

    // MARK: - Color Asset Grid

    /// Shows category assets tinted in each palette color. Tap to select color.
    private var colorAssetGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Color")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary.opacity(0.6))

            let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(CanvasColorPalette.paletteHex.enumerated()), id: \.offset) { index, hex in
                    let assetName = category == .body
                        ? categoryAssets[selectedAssetVariant]
                        : categoryAssets[index % categoryAssets.count]
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
        .padding(14)
        .glassCard()
    }

    // MARK: - Helpers

    private func saveEntry() {
        let dayKey = AppModel.dayKey(for: Date())
        let newEntry = OptionEntry(
            id: "\(option.id)_\(dayKey)",
            dayKey: dayKey,
            optionId: option.id,
            category: category,
            colorHex: selectedColorHex,
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            timestamp: Date(),
            assetVariant: category == .body ? selectedAssetVariant : nil
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
