import SwiftUI

// MARK: - Radial Hold Menu (tap to fan, or long-press+drag)

/// Tap shows 3 category buttons (Body / Mind / Heart) in a fan arc.
/// Long-press + drag also works: nodes appear and you can drag to select.
struct RadialHoldMenu: View {
    var labelColor: Color = .white
    let onCategorySelected: (EnergyCategory) -> Void
    var onFanOpened: (() -> Void)? = nil

    @State private var isFanOpen = false
    @GestureState private var dragOffset: CGSize = .zero
    @State private var isHolding = false
    @State private var hoveredCategory: EnergyCategory? = nil

    private let nodes: [(category: EnergyCategory, label: String, icon: String, angle: Double)] = [
        (.body,   String(localized: "Body", comment: "RadialMenu – energy category label"),  "figure.walk",       135),  // upper-left
        (.mind,   String(localized: "Mind", comment: "RadialMenu – energy category label"),  "brain.head.profile", 90),  // straight up
        (.heart,  String(localized: "Heart", comment: "RadialMenu – energy category label"), "heart.fill",         45),  // upper-right
    ]

    private let fanRadius: CGFloat = 80
    private let activationDistance: CGFloat = 55
    private static let hapticMedium = UIImpactFeedbackGenerator(style: .medium)
    private static let hapticLight = UIImpactFeedbackGenerator(style: .light)

    private func nodeOffset(angleDeg: Double) -> CGSize {
        let rad = angleDeg * .pi / 180
        return CGSize(width: cos(rad) * fanRadius, height: -sin(rad) * fanRadius)
    }

    var body: some View {
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
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isFanOpen)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isHolding)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: hoveredCategory)
    }

    // MARK: - Plus Button

    private var plusButton: some View {
        let holdAndDrag = LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
            .updating($dragOffset) { value, state, _ in
                if case .second(true, let drag?) = value {
                    state = drag.translation
                }
            }
            .onChanged { value in
                if case .second(true, let drag) = value {
                    if !isHolding {
                        isFanOpen = false
                        isHolding = true
                        Self.hapticMedium.impactOccurred()
                    }
                    if let drag = drag {
                        updateHoveredCategory(from: drag.translation)
                    }
                }
            }
            .onEnded { _ in
                if let category = hoveredCategory {
                    Self.hapticMedium.impactOccurred()
                    onCategorySelected(category)
                }
                isHolding = false
                hoveredCategory = nil
            }

        let isActive = isFanOpen || isHolding

        return ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .opacity(isActive ? 0.85 : 0.7)
                .frame(width: 56, height: 56)
            Circle()
                .strokeBorder(labelColor.opacity(isActive ? 0.5 : 0.3), lineWidth: 1)
                .frame(width: 56, height: 56)

            Image(systemName: isActive ? "xmark" : "plus")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(labelColor.opacity(isActive ? 0.7 : 0.85))
                .rotationEffect(.degrees(isFanOpen ? 45 : 0))
        }
        .frame(width: 72, height: 72)
        .contentShape(Circle())
        .accessibilityIdentifier("radial_plus_button")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            if isFanOpen { isFanOpen = false } else { isFanOpen = true; onFanOpened?() }
        }
        .gesture(holdAndDrag)
        .simultaneousGesture(
            TapGesture().onEnded {
                Self.hapticLight.impactOccurred()
                if isFanOpen {
                    isFanOpen = false
                } else {
                    isFanOpen = true
                    onFanOpened?()
                }
            }
        )
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
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .opacity(isHovered ? 0.9 : 0.7)
                    )
                    .overlay(
                        Circle()
                            .stroke(labelColor.opacity(isHovered ? 0.6 : 0.3), lineWidth: 1)
                    )
                    .scaleEffect(isHovered ? 1.15 : 1.0)

                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(labelColor.opacity(isHovered ? 0.9 : 0.7))
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("radial_\(category.rawValue)")
        .accessibilityLabel(label)
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
