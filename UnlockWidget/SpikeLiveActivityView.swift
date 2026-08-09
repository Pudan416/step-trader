import ActivityKit
import SwiftUI
import WidgetKit

/// Spike scaffolding, deliberately plain. This is a lamp, not the Feeds timer — it
/// exists only to make `lastUpdatedBy` readable without opening the app. Anything
/// beginning `monitor:` means the `DeviceActivityMonitor` extension reached
/// ActivityKit, which is the whole question. See `Feeds-Spike.md`.
struct SpikeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SpikeLiveActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 6) {
                Text(context.attributes.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("\(context.state.remainingMinutes) min")
                    .font(.system(.largeTitle, design: .monospaced))

                Text("\(context.state.lastUpdatedBy) · update #\(context.state.updateCount)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("\(context.state.remainingMinutes)m")
                        .font(.system(.title2, design: .monospaced))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("#\(context.state.updateCount)")
                        .font(.system(.title3, design: .monospaced))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.lastUpdatedBy)
                        .font(.system(.caption, design: .monospaced))
                }
            } compactLeading: {
                Text("\(context.state.remainingMinutes)")
                    .font(.system(.body, design: .monospaced))
            } compactTrailing: {
                Text(Self.originGlyph(context.state.lastUpdatedBy))
                    .font(.system(.body, design: .monospaced))
            } minimal: {
                Text(Self.originGlyph(context.state.lastUpdatedBy))
                    .font(.system(.body, design: .monospaced))
            }
        }
    }

    /// One character, so the answer is legible in the collapsed Dynamic Island:
    /// `M` for the monitor extension, `A` for the app that started the activity.
    private static func originGlyph(_ lastUpdatedBy: String) -> String {
        lastUpdatedBy.hasPrefix("monitor") ? "M" : "A"
    }
}
