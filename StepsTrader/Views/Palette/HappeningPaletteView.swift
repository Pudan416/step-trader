import SwiftUI

/// Palette container for the native Living-island field.
///
/// Chooser and creator controls intentionally remain out of this task. The
/// `onCreate` callback stays in the interface so their later implementation
/// does not force caller churn.
struct HappeningPaletteView: View {
    let happenings: [Happening]
    let onPick: (Happening) -> Void
    let onCreate: (String) -> Void
    let dayKey: String

    @Environment(\.dismiss) private var dismiss

    /// Relative luminance (WCAG), 0 = black, 1 = white.
    static func relativeLuminance(ofHex hex: String) -> Double {
        var raw = hex.trimmingCharacters(in: .whitespaces)
        if raw.hasPrefix("#") { raw.removeFirst() }
        guard raw.count == 6, let value = UInt32(raw, radix: 16) else { return 1 }

        func linear(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        let red = linear(Double((value >> 16) & 0xFF) / 255)
        let green = linear(Double((value >> 8) & 0xFF) / 255)
        let blue = linear(Double(value & 0xFF) / 255)
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    static func labelColor(onHex hex: String) -> Color {
        relativeLuminance(ofHex: hex) < 0.22
            ? .white.opacity(0.92)
            : .black.opacity(0.8)
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = HappeningLiquidLayout.layout(
                count: happenings.count,
                in: proxy.size,
                safeInsets: proxy.safeAreaInsets
            )

            ZStack(alignment: .topLeading) {
                HappeningLiquidField(
                    happenings: happenings,
                    dayKey: dayKey,
                    onPick: { happening, _ in onPick(happening) }
                )

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.82))
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay {
                            Circle().stroke(.white.opacity(0.18), lineWidth: 0.75)
                        }
                }
                .buttonStyle(.plain)
                .position(layout.dockAnchor)
                .accessibilityLabel(Text("Close", comment: "Palette close button"))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(Color.clear)
        }
        .presentationDetents([.large])
    }
}

#Preview("Living island palette") {
    HappeningPaletteView(
        happenings: HappeningDefaults.builtIns,
        onPick: { _ in },
        onCreate: { _ in },
        dayKey: "2026-08-09"
    )
}
