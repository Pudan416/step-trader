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
    @State private var presentation: HappeningLiquidPresentationState

    init(
        happenings: [Happening],
        onPick: @escaping (Happening) -> Void,
        onCreate: @escaping (String) -> Void,
        dayKey: String
    ) {
        self.happenings = happenings
        self.onPick = onPick
        self.onCreate = onCreate
        self.dayKey = dayKey
        _presentation = State(
            initialValue: HappeningLiquidPresentationState(happenings: happenings)
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = presentation.layout(in: proxy.size, safeInsets: proxy.safeAreaInsets)

            ZStack(alignment: .topLeading) {
                HappeningLiquidField(
                    happenings: happenings,
                    presentation: $presentation,
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
