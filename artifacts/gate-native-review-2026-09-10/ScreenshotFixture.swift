#if DEBUG
import SwiftUI

/// Debug-only launch shortcut: `-uiLab <name>` opens an experiment bench as the
/// app's root, skipping onboarding, tabs and settings.
///
/// This exists because verifying a shader means looking at it, and walking the
/// settings path with synthetic taps drops or misroutes them often enough that
/// the check costs more than the change being checked. Release builds never
/// compile this file's call site.
enum ExperimentalLabRoute: String, CaseIterable {
    case gateReview
    case dayObjects
    case shapeGenomeExport

    static var current: ExperimentalLabRoute? {
        // iOS folds `-key value` launch arguments into the NSArgumentDomain,
        // so the defaults lookup is the reliable read; the argv scan stays as
        // a fallback for launches that pass the flag some other way.
        if let name = UserDefaults.standard.string(forKey: "uiLab"),
           let route = ExperimentalLabRoute(rawValue: name) {
            return route
        }
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-uiLab"), index + 1 < arguments.count {
            return ExperimentalLabRoute(rawValue: arguments[index + 1])
        }
        return nil
    }

    @MainActor
    @ViewBuilder
    var view: some View {
        switch self {
        case .gateReview: GateScreenshotReview()
        case .dayObjects: DayObjectsLabView()
        case .shapeGenomeExport: MetalShapeAtlasExportView()
        }
    }
}
// Temporary screenshot fixture; this file is only in /private/tmp.
@MainActor
private struct GateScreenshotReview: View {
    @StateObject private var model: AppModel
    private let variant: String
    private let seed: UInt32

    init() {
        variant = UserDefaults.standard.string(forKey: "gateShot") ?? "paygate"
        seed = UInt32(UserDefaults.standard.string(forKey: "gateSeed") ?? "44100105") ?? 44100105
        let fixture = DIContainer.shared.makeAppModel()
        let group = TicketGroup(id: "gate-review", name: "Instagram",
                                settings: AppUnlockSettings(entryCostSteps: 4, dayPassCostSteps: 20))
        fixture.blockingStore.ticketGroups = [group]
        fixture.userEconomyStore.totalStepsBalance = variant == "empty" ? 2 : 32
        fixture.userEconomyStore.payGateTargetGroupId = group.id
        fixture.userEconomyStore.currentPayGateSessionId = group.id
        fixture.userEconomyStore.payGateSessions[group.id] = PayGateSession(
            id: group.id, groupId: group.id, startedAt: .now, artwork: GateArtwork(seed: seed))
        if variant == "reset" {
            let boundary = Calendar.current.date(byAdding: .minute, value: 23, to: .now)!
            fixture.dayEndHour = Calendar.current.component(.hour, from: boundary)
            fixture.dayEndMinute = Calendar.current.component(.minute, from: boundary)
        }
        _model = StateObject(wrappedValue: fixture)
    }

    var body: some View {
        Group {
            if variant.hasPrefix("shield") || variant.hasPrefix("tone") {
                shieldReconstruction
            } else {
                PayGateView(model: model)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var shieldReconstruction: some View {
        GeometryReader { geometry in
            ZStack {
                Color(red: 0.14, green: 0.14, blue: 0.18).ignoresSafeArea()
                VStack(spacing: 0) {
                    Spacer()
                    VStack(spacing: 14) {
                        if let icon = GateArtworkRenderer.image(GateArtwork(seed: seed), pointSize: 80) {
                            Image(uiImage: icon).resizable().scaledToFit().frame(width: 80, height: 80)
                        }
                        Text(shieldTitle)
                            .font(.system(size: 23, weight: .bold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)
                        Text(shieldSubtitle)
                            .font(.system(size: 22))
                            .lineSpacing(2)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.top, 18)
                    }
                    .padding(.horizontal, 24)
                    Spacer()
                    VStack(spacing: 12) {
                        Text(variant == "shield-sent" ? "one more push" : "unlock with push")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity).frame(height: 52)
                            .background(Color(red: 1, green: 211.0/255, blue: 105.0/255), in: Capsule())
                        Text("keep it closed")
                            .font(.system(size: 18))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(maxWidth: .infinity).frame(height: 52)
                            .background(.black.opacity(0.14), in: Capsule())
                            .overlay(Capsule().stroke(.white.opacity(0.08), lineWidth: 1))
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 14)
                }
            }
        }
    }

    private var shieldTitle: String {
        switch variant {
        case "tone-a": "your feeds\ncost colors"
        case "tone-b": "your colors.\nyour choice."
        case "tone-c": "feeds aren't evil.\njust expensive."
        default: "Instagram is locked\nby Nowhere."
        }
    }

    private var shieldSubtitle: String {
        if variant == "shield-sent" {
            return "Nowhere sent you a push.\nTap it to unlock Instagram."
        }
        if variant.hasPrefix("tone") {
            return "Spend colors\nto open Instagram."
        }
        return "Spend some colors\nto unlock it"
    }
}

#endif
