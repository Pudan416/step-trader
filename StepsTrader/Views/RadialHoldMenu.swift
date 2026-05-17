import SwiftUI

// MARK: - Radial Hold Menu (tap to fan, or long-press+drag)

/// Tap shows 3 category buttons (Body / Mind / Heart) in a fan arc.
/// Long-press + drag also works: nodes appear and you can drag to select.
struct RadialHoldMenu: View {
    var labelColor: Color = .white
    let onCategorySelected: (EnergyCategory) -> Void
    var onFanOpened: (() -> Void)? = nil

    @State private var isFanOpen = false
    @State private var isHolding = false
    @State private var hoveredCategory: EnergyCategory? = nil
    @State private var touchDownTime: Date? = nil
    @State private var holdActivated = false

    private let nodes: [(category: EnergyCategory, label: String, icon: String, angle: Double)] = [
        (.body,   String(localized: "Body", comment: "RadialMenu – energy category label"),  "figure.walk",       135),  // upper-left
        (.mind,   String(localized: "Mind", comment: "RadialMenu – energy category label"),  "brain.head.profile", 90),  // straight up
        (.heart,  String(localized: "Heart", comment: "RadialMenu – energy category label"), "heart.fill",         45),  // upper-right
    ]

    private let fanRadius: CGFloat = 80
    private let activationDistance: CGFloat = 55
    private static let hapticMedium = UIImpactFeedbackGenerator(style: .medium)
    private static let hapticLight = UIImpactFeedbackGenerator(style: .light)

    /// Warm up haptic generators so the first `impactOccurred()` doesn't pay cold-start latency
    /// (~50–150ms). Call once on appear and again when a touch begins so the engine stays hot
    /// across the user's actual gesture.
    static func prepareAll() {
        hapticMedium.prepare()
        hapticLight.prepare()
    }

    private func nodeOffset(angleDeg: Double) -> CGSize {
        let rad = angleDeg * .pi / 180
        return CGSize(width: cos(rad) * fanRadius, height: -sin(rad) * fanRadius)
    }

    var body: some View {
        // Wrap all glass children in a GlassEffectContainer. Without this, iOS 26
        // merges the interactive glass surfaces of the + button and the three
        // category nodes (Body/Mind/Heart) and routes every tap to the first one
        // — silently breaking the fan node taps.
        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: 0) { menuStack }
            } else {
                menuStack
            }
        }
    }

    @ViewBuilder
    private var menuStack: some View {
        ZStack {
            // Category nodes — visible in either fan-tap mode or hold-drag mode
            if isFanOpen || isHolding {
                ForEach(nodes, id: \.category) { node in
                    let offset = nodeOffset(angleDeg: node.angle)
                    categoryNode(
                        label: node.label,
                        icon: node.icon,
                        category: node.category,
                        isHovered: hoveredCategory == node.category,
                        offset: offset
                    )
                }
                .transition(.scale.combined(with: .opacity))
            }

            // + button with liquid dots
            plusButton
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isFanOpen || isHolding)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: hoveredCategory)
        .onAppear { Self.prepareAll() }
    }

    // MARK: - Plus Button

    private let holdThreshold: TimeInterval = 0.3

    private var plusButton: some View {
        let unifiedDrag = DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if touchDownTime == nil {
                    touchDownTime = Date()
                    holdActivated = false
                    Self.prepareAll()
                    scheduleHoldActivation()
                }
                if holdActivated {
                    updateHoveredCategory(from: value.translation)
                }
            }
            .onEnded { _ in
                let wasTap = !holdActivated
                if wasTap {
                    toggleFan()
                } else {
                    if let category = hoveredCategory {
                        Self.hapticMedium.impactOccurred()
                        onCategorySelected(category)
                    }
                    isHolding = false
                    hoveredCategory = nil
                }
                touchDownTime = nil
                holdActivated = false
            }

        let isActive = isFanOpen || isHolding

        return Image(systemName: isActive ? "xmark" : "plus")
            .font(.system(size: 22, weight: .regular))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(labelColor.opacity(isActive ? 0.85 : 1.0))
            .rotationEffect(.degrees(isFanOpen ? 45 : 0))
            .frame(width: 56, height: 56)
            .liquidGlassControl(in: Circle())
            .frame(width: 72, height: 72)
            .contentShape(Circle())
            .accessibilityIdentifier("radial_plus_button")
            .accessibilityLabel(isFanOpen
                ? String(localized: "Close menu", comment: "RadialMenu – VoiceOver label")
                : String(localized: "Add activity", comment: "RadialMenu – VoiceOver label"))
            .accessibilityHint(String(localized: "Hold and drag to quickly select a category, or tap to open the menu", comment: "RadialMenu – VoiceOver hint"))
            .accessibilityAddTraits(.isButton)
            .simultaneousGesture(unifiedDrag)
    }

    private func scheduleHoldActivation() {
        DispatchQueue.main.asyncAfter(deadline: .now() + holdThreshold) {
            guard touchDownTime != nil else { return }
            holdActivated = true
            isFanOpen = false
            isHolding = true
            Self.hapticMedium.impactOccurred()
            Self.prepareAll()
        }
    }

    private func toggleFan() {
        Self.hapticLight.impactOccurred()
        if isFanOpen {
            isFanOpen = false
        } else {
            isFanOpen = true
            onFanOpened?()
        }
        UIAccessibility.post(notification: .layoutChanged, argument: nil)
    }

    // MARK: - Category Node

    private func categoryNode(
        label: String,
        icon: String,
        category: EnergyCategory,
        isHovered: Bool,
        offset: CGSize
    ) -> some View {
        Button {
            if isFanOpen {
                Self.hapticMedium.impactOccurred()
                onCategorySelected(category)
                isFanOpen = false
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: isHovered ? 20 : 16, weight: .medium))
                    .foregroundStyle(labelColor.opacity(isHovered ? 1.0 : 0.85))
                    .frame(width: 44, height: 44)
                    .liquidGlassControl(in: Circle())
                    .scaleEffect(isHovered ? 1.15 : 1.0)

                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(labelColor.opacity(isHovered ? 1.0 : 0.9))
                    .contrastingOnGlass()
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("radial_\(category.rawValue)")
        .accessibilityLabel(Text("\(label) category"))
        .accessibilityAddTraits(.isButton)
        #if DEBUG
        .modifier(MindNodeAnchor(category: category))
        #endif
        .offset(offset)
    }

    // MARK: - Hit Testing (drag mode)

    private func updateHoveredCategory(from translation: CGSize) {
        var closest: EnergyCategory? = nil
        var closestDist: CGFloat = .infinity

        for node in nodes {
            let off = nodeOffset(angleDeg: node.angle)
            let dx = translation.width - off.width
            let dy = translation.height - off.height
            let dist = sqrt(dx * dx + dy * dy)
            if dist < activationDistance && dist < closestDist {
                closest = node.category
                closestDist = dist
            }
        }

        if closest != hoveredCategory {
            if closest != nil {
                Self.hapticLight.impactOccurred()
            }
            hoveredCategory = closest
        }
    }
}

#if DEBUG
private struct MindNodeAnchor: ViewModifier {
    let category: EnergyCategory
    func body(content: Content) -> some View {
        if category == .mind {
            content.coachMarkAnchor(.tapMind)
        } else {
            content
        }
    }
}
#endif

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            Spacer()
            RadialHoldMenu(labelColor: .white) { category in
                AppLogger.ui.debug("Selected: \(category.rawValue)")
            }
            .padding(.bottom, 80)
        }
    }
}
