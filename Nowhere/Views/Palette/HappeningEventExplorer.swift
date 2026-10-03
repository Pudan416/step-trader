import SwiftUI

struct HappeningEventExplorer: View {
    let onChoose: (HappeningEventNode) -> Void
    let onRemove: (HappeningEventNode) -> Void
    let remaining: Int
    let addedIDs: Set<String>
    let onFinish: () -> Void

    @State private var isBrowsingAll = false
    @State private var visibleEvents = HappeningEventTree.startingEvents
    @State private var armedMutation: HappeningPaletteMutation?
    @State private var isTransitioning = false

    private let ink = Color(hex: "24372B")
    private let paper = Color(hex: "F4F5EF")
    private let circleDiameter: CGFloat = 112

    var body: some View {
        GeometryReader { proxy in
            let points = circlePoints(in: proxy.size)
            ZStack {
                paper.ignoresSafeArea()

                ForEach(Array(visibleEvents.enumerated()), id: \.element.id) { index, event in
                    if index < points.count {
                        eventCircle(event)
                            .position(points[index])
                    }
                }

                dateHub
                    .position(CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2))

                VStack {
                    HStack {
                Button(isBrowsingAll ? "Tree" : "All") {
                    isBrowsingAll.toggle()
                    armedMutation = nil
                    visibleEvents = isBrowsingAll
                        ? HappeningEventTree.startingEvents
                        : Array(HappeningEventTree.all.shuffled().prefix(6))
                        }
                        .eventExplorerPill(ink: ink)

                        Spacer()

                        Button("Done", action: onFinish)
                            .eventExplorerPill(ink: ink)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, proxy.safeAreaInsets.top + 8)

                    Spacer()

                    HStack {
                        Text("\(remaining) left today")
                        Spacer()
                        Button("Finish day", action: onFinish)
                    }
                    .font(.custom("Onest-Medium", size: 14))
                    .foregroundStyle(ink)
                    .padding(.horizontal, 22)
                    .padding(.bottom, max(20, proxy.safeAreaInsets.bottom + 12))
                }
            }
            .animation(.spring(response: 0.48, dampingFraction: 0.76), value: visibleEvents.map(\.id))
        }
        .preferredColorScheme(.light)
        .onAppear { visibleEvents = HappeningEventTree.startingEvents }
    }

    private var dateHub: some View {
        VStack(spacing: 4) {
            Text(Date.now, format: .dateTime.month(.abbreviated).day())
                .font(.custom("NowhereDisplay091-Regular", size: 26))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("\(10 - remaining) / 10")
                .font(.custom("Onest-Medium", size: 11))
                .monospacedDigit()
        }
        .foregroundStyle(ink)
        .frame(width: 116, height: 116)
        .background(Circle().fill(paper))
        .overlay(Circle().strokeBorder(ink.opacity(0.10), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Date.now.formatted(.dateTime.month(.abbreviated).day()))
    }

    private func eventCircle(_ event: HappeningEventNode) -> some View {
        let isAdded = addedIDs.contains(event.id)
        let isArmed = armedMutation?.id == event.id
        let isRemoval = armedMutation == .remove(event.id)

        return Button {
            guard !isTransitioning else { return }
            let intended: HappeningPaletteMutation = isAdded ? .remove(event.id) : .add(event.id)
            if armedMutation == intended {
                armedMutation = nil
                isTransitioning = true
                if isAdded { onRemove(event) } else { onChoose(event) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { isTransitioning = false }
                let current = Set(visibleEvents.map(\.id)).union(addedIDs)
                let newEvents = HappeningEventTree.suggestions(for: event, alreadyVisible: current)
                if !newEvents.isEmpty { visibleEvents.append(contentsOf: newEvents) }
            } else {
                armedMutation = intended
            }
        } label: {
            VStack(spacing: 5) {
                Text(event.title)
                    .font(.custom("Onest-SemiBold", size: 15))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                if isArmed {
                    Text(isRemoval ? "Tap to remove" : "Tap to add")
                        .font(.custom("Onest-Medium", size: 10))
                        .lineLimit(1)
                } else if isAdded {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                }
            }
            .foregroundStyle(isArmed && isRemoval ? Color.white : ink)
            .frame(width: circleDiameter, height: circleDiameter)
            .background(Circle().fill(isArmed && isRemoval ? ink : .white.opacity(0.94)))
            .overlay(Circle().strokeBorder(ink.opacity(isAdded ? 0.55 : 0.12), lineWidth: isAdded ? 2 : 1))
            .shadow(color: ink.opacity(0.08), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("event_circle_\(event.id)")
    }

    private func circlePoints(in size: CGSize) -> [CGPoint] {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let firstRadius = min(size.width * 0.33, max(112, min(size.height * 0.235, 190)))
        var result = (0..<min(6, visibleEvents.count)).map { index in
            let angle = -CGFloat.pi / 2 + CGFloat(index) * .pi / 3
            return CGPoint(x: center.x + cos(angle) * firstRadius, y: center.y + sin(angle) * firstRadius)
        }
        let extraCount = max(0, visibleEvents.count - 6)
        if extraCount > 0 {
            let outerRadius = min(size.width * 0.45, max(208, firstRadius * 1.75))
            for index in 0..<extraCount {
                let angle = -CGFloat.pi / 2 + CGFloat(index) * 2 * .pi / CGFloat(max(extraCount, 4))
                result.append(CGPoint(x: center.x + cos(angle) * outerRadius, y: center.y + sin(angle) * outerRadius))
            }
        }
        return result
    }
}

private extension View {
    func eventExplorerPill(ink: Color) -> some View {
        font(.custom("Onest-SemiBold", size: 14))
            .foregroundStyle(ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.white.opacity(0.92), in: Capsule())
    }
}
