import SwiftUI
#if canImport(FamilyControls)
import FamilyControls
#endif

// MARK: - Paper Ticket View (museum-style)

/// A ticket that looks like a simplified paper museum ticket.
/// Left stub (icon) | dashed perforation | main body (title, status, apps count)
/// Back side shows unlock buttons + settings gear when flipped.
struct PaperTicketView: View {
    @ObservedObject var model: AppModel
    let group: TicketGroup
    let appLanguage: String = "en"
    let colorScheme: ColorScheme
    let isFlipped: Bool
    var onSettings: () -> Void = {}
    var onFlip: () -> Void = {}

    @State private var isUnlocking = false

    private var frontFill: Color { AppColors.brandAccent }
    private var backSurface: Color { Color(red: 0xF2/255.0, green: 0xF2/255.0, blue: 0xF2/255.0) }
    private var backIsDark: Bool { false } // back is always light

    private var frontInk: Color { .black }
    private var frontSecondaryInk: Color { .black }
    private var backInk: Color { .black }
    private var backSecondaryInk: Color { .black }

    private var isUnlocked: Bool { model.isGroupUnlocked(group.id) }
    private var appsCount: Int {
        group.selection.applicationTokens.count + group.selection.categoryTokens.count
    }
    private let intervals: [AccessWindow] = [.minutes10, .minutes30, .hour1]

    private var spentToday: Int {
        model.appStepsSpentToday["group_\(group.id)"] ?? 0
    }
    private var spentLifetime: Int {
        model.totalStepsSpent(for: "group_\(group.id)")
    }

    var body: some View {
        Group {
            if isFlipped {
                backRayCard
            } else {
                frontRayCard
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isFlipped)
    }

    // MARK: - Front/back ray cards

    private var frontRayCard: some View {
        ZStack {
            RayCapsuleSurface(baseColor: frontFill, direction: .left)

            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0x1C/255.0, green: 0x1B/255.0, blue: 0x1B/255.0))  // #1C1B1B
                    ticketIcon
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                }
                .frame(width: 38, height: 38)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(ticketTitle)
                            .font(.system(size: 15, weight: .regular, design: .rounded))
                            .foregroundStyle(Color.black)
                            .lineLimit(1)
                        Spacer()
                        HStack(spacing: 3) {
                            Image(systemName: isUnlocked ? "lock.open" : "lock.fill")
                                .font(.system(size: 8, weight: .regular))
                            Text(isUnlocked ? "open" : "active")
                                .font(.system(size: 11, weight: .light, design: .rounded))
                        }
                        .foregroundStyle(activeStatusColor)
                    }

                    HStack(spacing: 12) {
                        HStack(spacing: 3) {
                            Image(systemName: "app").font(.system(size: 9, weight: .light))
                            Text("\(appsCount)")
                                .font(.system(size: 11, weight: .light, design: .rounded))
                        }
                        HStack(spacing: 3) {
                            Image(systemName: "bolt").font(.system(size: 9, weight: .light))
                            Text("\(spentToday)")
                                .font(.system(size: 11, weight: .light, design: .rounded))
                                .monospacedDigit()
                        }
                    }
                    .foregroundStyle(Color.black.opacity(0.55))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 14)
            .padding(.trailing, 16)
            .padding(.vertical, 10)
        }
        .frame(height: 90)
        .contentShape(Rectangle())
        .onTapGesture { onFlip() }
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    if abs(value.translation.width) > 50 {
                        onFlip()
                    }
                }
        )
    }

    private var backRayCard: some View {
        ZStack {
            RayCapsuleSurface(baseColor: backSurface, direction: .right)

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        onFlip()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 9, weight: .regular))
                            Text("Back")
                                .font(.system(size: 10, weight: .regular, design: .rounded))
                        }
                        .foregroundStyle(Color.black.opacity(0.75))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .strokeBorder(Color.black.opacity(0.25), lineWidth: 0.7)
                        )
                    }
                    .buttonStyle(.plain)

                    if isUnlocked {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.open")
                                .font(.system(size: 10, weight: .regular))
                            if let remaining = model.remainingUnlockTime(for: group.id), remaining > 0 {
                                Text(formatMinuteTimer(remaining))
                                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                            } else {
                                Text("Open")
                                    .font(.system(size: 12, weight: .regular, design: .rounded))
                            }
                            Spacer()
                        }
                        .foregroundStyle(Color.black.opacity(0.8))
                    } else {
                        let enabledIntervals = intervals.filter { group.enabledIntervals.contains($0) }
                        HStack(spacing: 4) {
                            ForEach(enabledIntervals, id: \.self) { interval in
                                unlockPill(interval: interval)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    onSettings()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0x22/255.0, green: 0x28/255.0, blue: 0x31/255.0))  // #222831
                        Image(systemName: "gearshape")
                            .font(.system(size: 15, weight: .light))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .frame(width: 36, height: 36)
                    .frame(width: 54, height: 90)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 90)
        .contentShape(Rectangle())
        .onTapGesture { onFlip() }
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    if abs(value.translation.width) > 50 {
                        onFlip()
                    }
                }
        )
    }

    // MARK: - Unlock pill button

    private func unlockPill(interval: AccessWindow) -> some View {
        let cost = group.cost(for: interval)
        let canAfford = model.userEconomyStore.totalStepsBalance >= cost
        let label = interval.displayName

        return Button {
            guard canAfford, !isUnlocking else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            Task {
                isUnlocking = true
                await model.handlePayGatePaymentForGroup(groupId: group.id, window: interval, costOverride: cost)
                isUnlocking = false
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "lock.open").font(.system(size: 8, weight: .medium))
                Text("\(label)·\(cost)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .foregroundStyle(Color.black)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(AppColors.brandAccent)  // #FFD369
            )
        }
        .buttonStyle(.plain)
        .opacity(canAfford ? 1.0 : 0.35)
        .disabled(!canAfford || isUnlocking)
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var ticketIcon: some View {
        if let templateApp = group.templateApp,
           let imageName = TargetResolver.imageName(for: templateApp),
           let uiImage = UIImage(named: imageName) ?? UIImage(named: imageName.lowercased()) ?? UIImage(named: imageName.capitalized) {
            Image(uiImage: uiImage)
                .resizable().scaledToFill()
        } else {
            #if canImport(FamilyControls)
            if let firstToken = group.selection.applicationTokens.first {
                AppIconView(token: firstToken)
            } else if let firstCat = group.selection.categoryTokens.first {
                CategoryIconView(token: firstCat)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 18)).foregroundStyle(.white.opacity(0.6))
            }
            #else
            Image(systemName: "app.fill")
                .font(.system(size: 18)).foregroundStyle(.white.opacity(0.6))
            #endif
        }
    }

    /// "Active" badge color: yellow (#FFD369) in night mode, black in day mode.
    private var activeStatusColor: Color {
        colorScheme == .dark
            ? Color(red: 0xFF/255, green: 0xD3/255, blue: 0x69/255)   // #FFD369
            : .black
    }

    private var ticketTitle: String {
        if let templateApp = group.templateApp {
            return TargetResolver.displayName(for: templateApp)
        }
        #if canImport(FamilyControls)
        let defaults = UserDefaults(suiteName: "group.personal-project.StepsTrader") ?? .standard
        if appsCount == 1, let firstToken = group.selection.applicationTokens.first,
           let tokenData = try? NSKeyedArchiver.archivedData(withRootObject: firstToken, requiringSecureCoding: true) {
            let tokenKey = "fc_appName_" + tokenData.base64EncodedString()
            if let name = defaults.string(forKey: tokenKey) { return name }
        }
        #endif
        if appsCount == 0 { return "Empty Ticket" }
        return group.name.isEmpty ? "\(appsCount) \(appsCount == 1 ? "app" : "apps")" : group.name
    }

}

enum RayDirection {
    case left
    case right
}

/// Native SwiftUI recreation of ray SVG surfaces:
/// - `ray 1`: radial shade anchored on the left
/// - `ray 2`: radial shade anchored on the right
struct RayCapsuleSurface: View {
    let baseColor: Color
    let direction: RayDirection

    // Extracted from ray1/ray2 SVGs: 341x65 with radial stop at 0.889432.
    private let gradientStop: CGFloat = 0.889432
    private let radiusScale: CGFloat = 310.5 / 341.0

    private var center: UnitPoint {
        switch direction {
        case .left:
            return UnitPoint(x: 26.0 / 341.0, y: 32.5 / 65.0)
        case .right:
            return UnitPoint(x: 315.0 / 341.0, y: 32.5 / 65.0)
        }
    }

    private var alphaGradient: LinearGradient {
        switch direction {
        case .left:
            // Front side: bright left -> transparent right.
            return LinearGradient(
                stops: [
                    .init(color: .white, location: 0.00),
                    .init(color: .white.opacity(0.75), location: 0.20),
                    .init(color: .white.opacity(0.50), location: 0.35),
                    .init(color: .white.opacity(0.20), location: 0.50),
                    .init(color: .clear, location: 0.75)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .right:
            // Back side: bright right -> transparent left.
            return LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.25),
                    .init(color: .white.opacity(0.20), location: 0.50),
                    .init(color: .white.opacity(0.50), location: 0.65),
                    .init(color: .white.opacity(0.75), location: 0.80),
                    .init(color: .white, location: 1.00)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            Capsule()
                .fill(baseColor)
                .overlay(
                    Capsule().fill(
                        RadialGradient(
                            stops: [
                                .init(color: .black.opacity(0.12), location: 0),
                                .init(color: .clear, location: gradientStop)
                            ],
                            center: center,
                            startRadius: 0,
                            endRadius: width * radiusScale
                        )
                    )
                )
                .mask(
                    Capsule()
                        .fill(alphaGradient)
                )
        }
    }
}
