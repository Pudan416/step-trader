import SwiftUI

// MARK: - Color Palette View

/// Curated grid of harmonious colors optimized for the unified gradient canvas.
/// Used when confirming an activity to pick the visual element's color.
struct ColorPaletteView: View {
    @Binding var selectedHex: String
    let onConfirm: () -> Void
    @Environment(\.appTheme) private var theme
    @ScaledMetric(relativeTo: .body) private var colorDotSize: CGFloat = 44

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        VStack(spacing: 12) {
            Text(String(localized: "Pick a color", comment: "ColorPalette – sheet title"))
                .font(.footnote.weight(.semibold))
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
                Text(String(localized: "Add", comment: "ColorPalette – add button"))
                    .font(.subheadline.weight(.semibold))
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
                .frame(width: colorDotSize, height: colorDotSize)
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

// MARK: - Preview

#Preview("Color Palette") {
    ZStack {
        Color.black.ignoresSafeArea()
        ColorPaletteView(selectedHex: .constant("#C3143B")) {
            AppLogger.ui.debug("Confirmed")
        }
        .padding(20)
    }
}
