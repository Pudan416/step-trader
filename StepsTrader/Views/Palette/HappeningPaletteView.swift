import SwiftUI

/// Palette container for the native Living-island field and catalog controls.
struct HappeningPaletteView: View {
    let happenings: [Happening]
    let catalog: [Happening]
    let selectedIDs: [String]
    let onPick: (Happening, CGPoint) -> Bool
    let onCreate: (String) -> Happening?
    let onSaveSelection: ([String]) -> Bool
    let onDismiss: () -> Void
    let dayKey: String

    @State private var presentation: HappeningLiquidPresentationState
    @State private var activePanel: Panel?
    @State private var highlightedID: String?
    @State private var highlightTask: Task<Void, Never>?

    private enum Panel {
        case chooser
        case creator
    }

    init(
        happenings: [Happening],
        catalog: [Happening]? = nil,
        selectedIDs: [String]? = nil,
        onPick: @escaping (Happening, CGPoint) -> Bool,
        onCreate: @escaping (String) -> Happening?,
        onSaveSelection: @escaping ([String]) -> Bool = { _ in true },
        onDismiss: @escaping () -> Void,
        dayKey: String
    ) {
        self.happenings = happenings
        self.catalog = catalog ?? happenings
        self.selectedIDs = selectedIDs ?? happenings.map(\.id)
        self.onPick = onPick
        self.onCreate = onCreate
        self.onSaveSelection = onSaveSelection
        self.onDismiss = onDismiss
        self.dayKey = dayKey
        _presentation = State(
            initialValue: HappeningLiquidPresentationState(happenings: happenings)
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = presentation.layout(in: proxy.size, safeInsets: proxy.safeAreaInsets)

            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard activePanel == nil else { return }
                        onDismiss()
                    }

                HappeningLiquidField(
                    happenings: happenings,
                    presentation: $presentation,
                    dayKey: dayKey,
                    highlightedID: highlightedID,
                    onPick: onPick
                )
                .accessibilityHidden(activePanel != nil)

                Button {
                    activePanel = nil
                    onDismiss()
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
                .accessibilityHidden(activePanel != nil)

                dockButton(
                    systemImage: "checklist",
                    label: "Choose happenings",
                    anchor: CGPoint(x: layout.dockAnchor.x - 56, y: layout.dockAnchor.y)
                ) {
                    activePanel = .chooser
                }
                .accessibilityHidden(activePanel != nil)

                dockButton(
                    systemImage: "plus",
                    label: "Add a happening",
                    anchor: CGPoint(x: layout.dockAnchor.x + 56, y: layout.dockAnchor.y)
                ) {
                    activePanel = .creator
                }
                .accessibilityHidden(activePanel != nil)

                if let activePanel {
                    Color.black.opacity(0.28)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {}
                        .transition(.opacity)

                    panel(for: activePanel)
                        .padding(20)
                        .frame(maxWidth: proxy.size.width, maxHeight: proxy.size.height)
                        .transition(.scale(scale: 0.96).combined(with: .opacity))
                        .zIndex(1)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(Color.clear)
        }
        .onChange(of: selectedIDs) {
            presentation.reset(with: happenings)
        }
        .onChange(of: dayKey) {
            presentation.reset(with: happenings)
        }
        .onDisappear {
            highlightTask?.cancel()
            highlightTask = nil
        }
    }

    @ViewBuilder
    private func panel(for panel: Panel) -> some View {
        switch panel {
        case .chooser:
            HappeningChooserView(
                catalog: catalog,
                selected: selectedIDs,
                onSave: { ids in
                    if onSaveSelection(ids) {
                        activePanel = nil
                    }
                },
                onCancel: { activePanel = nil }
            )
        case .creator:
            HappeningCreatorPanel(
                onCreate: { title in
                    guard let created = onCreate(title) else { return }
                    activePanel = nil
                    highlightedID = created.id
                    highlightTask?.cancel()
                    highlightTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(900))
                        guard !Task.isCancelled else { return }
                        highlightedID = nil
                    }
                },
                onCancel: { activePanel = nil }
            )
        }
    }

    private func dockButton(
        systemImage: String,
        label: String,
        anchor: CGPoint,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.82))
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle().stroke(.white.opacity(0.18), lineWidth: 0.75)
                }
        }
        .buttonStyle(.plain)
        .position(anchor)
        .accessibilityLabel(Text(label))
    }
}

#Preview("Living island palette") {
    HappeningPaletteView(
        happenings: HappeningDefaults.builtIns,
        catalog: HappeningDefaults.builtIns + [
            Happening(id: "user_sauna", title: "Sauna", isBuiltIn: false)
        ],
        selectedIDs: HappeningDefaults.builtIns.map(\.id),
        onPick: { _, _ in true },
        onCreate: { _ in nil },
        onDismiss: {},
        dayKey: "2026-08-09"
    )
}
