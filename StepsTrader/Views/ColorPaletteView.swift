import SwiftUI

// MARK: - Color Palette View

/// Curated grid of harmonious colors optimized for the unified gradient canvas.
/// Used when confirming an activity to pick the visual element's color.
struct ColorPaletteView: View {
    @Binding var selectedHex: String
    let onConfirm: () -> Void
    @Environment(\.appTheme) private var theme

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        VStack(spacing: 12) {
            Text("Pick a color")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.textPrimary.opacity(0.6))

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(CanvasColorPalette.paletteHex, id: \.self) { hex in
                    colorDot(hex: hex)
                }
            }
            .padding(.horizontal, 8)

            Button {
                onConfirm()
            } label: {
                Text("Add to canvas")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.isLightTheme ? .white : .black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        Capsule().fill(Color(hex: selectedHex))
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }

    private func colorDot(hex: String) -> some View {
        let isSelected = hex == selectedHex
        return Button {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                selectedHex = hex
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Circle()
                .fill(Color(hex: hex))
                .frame(width: 32, height: 32)
                .overlay(
                    Circle()
                        .stroke(.white, lineWidth: isSelected ? 2.5 : 0)
                )
                .overlay(
                    Circle()
                        .stroke(.black.opacity(0.15), lineWidth: 1)
                )
                .scaleEffect(isSelected ? 1.1 : 1.0)
                .shadow(color: isSelected ? Color(hex: hex).opacity(0.5) : .clear, radius: 6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Activity Picker with Color (wraps existing list + adds color)

struct ActivityPickerWithColorSheet: View {
    @ObservedObject var model: AppModel
    let initialCategory: EnergyCategory
    let onActivityConfirmed: (String, EnergyCategory, String) -> Void  // (optionId, category, hexColor)
    let onActivityUndo: (String, EnergyCategory) -> Void               // (optionId, category) — remove from canvas + toggle off
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tab: EnergyCategory = .body
    @State private var pendingOptionId: String? = nil
    @State private var selectedColorHex: String = CanvasColorPalette.paletteHex[0]
    @State private var showColorPicker = false
    @State private var showConfirm = false
    @State private var showUndoAlert = false
    @State private var undoOptionId: String? = nil
    @State private var undoCategory: EnergyCategory? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // Minimalist header
                HStack {
                    Text("Add activity")
                        .font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Button("Done") { 
                        onDismiss()
                        dismiss() 
                    }
                    .font(.system(size: 15, weight: .medium))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                
                Picker("", selection: $tab) {
                    Text("Body").tag(EnergyCategory.body)
                    Text("Mind").tag(EnergyCategory.mind)
                    Text("Heart").tag(EnergyCategory.heart)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(options(for: tab)) { option in
                            activityRow(option: option, category: tab)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, showColorPicker ? 240 : 16)
                }

                // Color picker overlay
                if showColorPicker {
                    ColorPaletteView(selectedHex: $selectedColorHex) {
                        confirmSelection()
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: showColorPicker)
        }
        .onAppear { tab = initialCategory }
        .presentationDetents([.height(480), .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .height(480)))
        .alert("Undo this action?", isPresented: $showUndoAlert) {
            Button("Cancel", role: .cancel) {
                undoOptionId = nil
                undoCategory = nil
            }
            Button("Undo", role: .destructive) {
                if let optionId = undoOptionId, let category = undoCategory {
                    onActivityUndo(optionId, category)
                }
                undoOptionId = nil
                undoCategory = nil
            }
        } message: {
            Text("This will remove the activity from today's canvas and unmark it.")
        }
    }

    private func options(for category: EnergyCategory) -> [EnergyOption] {
        model.orderedOptions(for: category)
    }

    @ViewBuilder
    private func activityRow(option: EnergyOption, category: EnergyCategory) -> some View {
        let isSelected = model.isDailySelected(option.id, category: category)
        let canSelect = !isSelected && model.dailySelectionsCount(for: category) < EnergyDefaults.maxSelectionsPerCategory

        Button {
            if isSelected {
                undoOptionId = option.id
                undoCategory = category
                showUndoAlert = true
                return
            }
            guard canSelect else { return }
            pendingOptionId = option.id
            selectedColorHex = defaultColorHex(for: category)
            showColorPicker = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: option.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isSelected ? .yellow : .primary)
                    .frame(width: 24)
                Text(option.title(for: "en"))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.yellow)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(canSelect || isSelected ? 1 : 0.4)
    }

    private func defaultColorHex(for category: EnergyCategory) -> String {
        switch category {
        case .body:   return "#C3143B"  // Red
        case .mind:   return "#7652AF"  // Purple
        case .heart:  return "#FEAAC2"  // Light pink
        }
    }

    private func confirmSelection() {
        guard let optionId = pendingOptionId else { return }
        // Toggle in model
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            model.toggleDailySelection(optionId: optionId, category: tab)
        }
        // Spawn canvas element
        onActivityConfirmed(optionId, tab, selectedColorHex)
        // Reset
        showColorPicker = false
        pendingOptionId = nil
    }
}

// MARK: - Preview

#Preview("Color Palette") {
    ZStack {
        Color.black.ignoresSafeArea()
        ColorPaletteView(selectedHex: .constant("#C3143B")) {
            print("Confirmed")
        }
        .padding(20)
    }
}
