import SwiftUI

/// A disc with the spent portion cut away, sweeping clockwise from twelve.
///
/// `fraction` is the share of the window still unspent, so 1 is a whole disc
/// and 0 is nothing. The cut runs from the centre, which is what makes it read
/// as a mass being consumed rather than as a progress arc.
///
/// Deliberately not `Animatable`: `UnlockTimerModel` reports whole minutes, and
/// interpolating between them would draw time the app has not been told about.
/// A tick lands as a hard cut.
struct DepletionWedge: Shape {
    /// Share of the window remaining, 0…1.
    var fraction: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let clamped = max(0, min(1, fraction))
        guard clamped > 0 else { return path }

        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2

        guard clamped < 1 else {
            path.addEllipse(in: CGRect(
                x: centre.x - radius,
                y: centre.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            return path
        }

        path.move(to: centre)
        path.addArc(
            center: centre,
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * clamped),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}
