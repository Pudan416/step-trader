import XCTest
import SwiftUI
import Observation
@testable import Steps4

@MainActor
final class DailyInterfaceColorTests: XCTestCase {
    func testLegacyAccentAccessInvalidatesAndPayGateUsesEachDailyFamily() async throws {
        let originalChrome = TodayCanvasBackdropStore.shared.chromePalette
        let originalDay = DailyInterfaceColors.shared.palette.dayKey
        defer { DailyInterfaceColors.shared.update(originalChrome, dayKey: originalDay, reloadWidgets: {}) }
        let model = DIContainer.shared.makeAppModel()
        let group = TicketGroup(id: "daily-color-review", name: "Instagram", settings: AppUnlockSettings(entryCostSteps: 4, dayPassCostSteps: 20))
        model.blockingStore.ticketGroups = [group]
        model.userEconomyStore.totalStepsBalance = 32
        model.userEconomyStore.payGateTargetGroupId = group.id
        model.userEconomyStore.currentPayGateSessionId = group.id
        model.userEconomyStore.payGateSessions[group.id] = PayGateSession(id: group.id, groupId: group.id, startedAt: .now, artwork: GateArtwork(seed: 3))
        let host = UIHostingController(rootView: PayGateView(model: model).font(AppFonts.body).preferredColorScheme(.dark).frame(width: 390, height: 844))
        host.safeAreaRegions = []
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        defer { window.isHidden = true }
        var captures: [Data] = []
        for (name, hex) in [("sage", "78966B"), ("blue", "6987A5"), ("lilac", "9581AA"), ("clay", "AE7E68")] {
            var changed = false
            withObservationTracking { _ = AppColors.brandAccent } onChange: { changed = true }
            let chrome = CanvasChromePalette.resolve(backgroundColors: [DayObjectRGB(hex: hex)])
            let previous = DailyInterfaceColors.shared.palette.accent
            DailyInterfaceColors.shared.update(chrome, dayKey: "2026-09-11", reloadWidgets: {})
            if previous != DailyInterfaceColors.shared.palette.accent { XCTAssertTrue(changed) }
            func assertRGB(_ color: Color, equals expected: DailyInterfacePalette.RGB) {
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                XCTAssertTrue(UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a))
                XCTAssertEqual(Double(r), expected.red, accuracy: 0.00001)
                XCTAssertEqual(Double(g), expected.green, accuracy: 0.00001)
                XCTAssertEqual(Double(b), expected.blue, accuracy: 0.00001)
            }
            assertRGB(AppColors.brandAccent, equals: DailyInterfaceColors.shared.palette.accent)
            assertRGB(AppTheme.daylight.accentColor, equals: DailyInterfaceColors.shared.palette.ink)
            try await Task.sleep(for: .milliseconds(700))
            host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: CGRect(x: 0, y: 0, width: 390, height: 844)).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            captures.append(try XCTUnwrap(image.pngData()))
            let attachment = XCTAttachment(image: image)
            attachment.name = "PayGate-\(name)"; attachment.lifetime = .keepAlways; add(attachment)
        }
        XCTAssertEqual(Set(captures).count, 4, "The already-mounted PayGate must recolor without recreation")
    }
}
