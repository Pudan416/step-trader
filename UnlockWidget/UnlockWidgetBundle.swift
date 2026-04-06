//
//  UnlockWidgetBundle.swift
//  UnlockWidget
//
//  Created by Konstantin Pudan on 23.03.2026.
//

import WidgetKit
import SwiftUI

@main
struct UnlockWidgetBundle: WidgetBundle {
    var body: some Widget {
        StatusWidget()
        GroupsWidget()
        ComboWidget()
    }
}

struct StatusWidget: Widget {
    let kind = WidgetKind.status

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: StatusTimelineProvider()
        ) { entry in
            UnlockWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Energy Status")
        .description("Today's colors and energy breakdown.")
        .supportedFamilies([.systemMedium])
    }
}

struct GroupsWidget: Widget {
    let kind = WidgetKind.main

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectGroupIntent.self,
            provider: UnlockTimelineProvider()
        ) { entry in
            UnlockWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("App Groups")
        .description("Unlock and manage app groups.")
        .supportedFamilies([.systemLarge])
    }
}

struct ComboWidget: Widget {
    let kind = WidgetKind.combo

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectSingleGroupIntent.self,
            provider: ComboTimelineProvider()
        ) { entry in
            ComboWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Energy + App")
        .description("Energy bar with one app group for quick unlock.")
        .supportedFamilies([.systemMedium])
    }
}
