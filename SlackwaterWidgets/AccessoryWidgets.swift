// Slackwater — GPL v3. Premium lock-screen widgets.
import SwiftUI
import WidgetKit

struct SlackInlineWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "SlackInline", intent: StationConfigIntent.self,
                               provider: StationProvider()) { entry in
            AccessoryWidgetView(entry: entry, family: .accessoryInline)
        }
        .configurationDisplayName("Next Slack")
        .description("The next event, above the clock.")
        .supportedFamilies([.accessoryInline])
    }
}

struct SlackCircularWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "SlackCircular", intent: StationConfigIntent.self,
                               provider: StationProvider()) { entry in
            AccessoryWidgetView(entry: entry, family: .accessoryCircular)
        }
        .configurationDisplayName("Next Event")
        .description("Next slack or turn at a glance.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct SlackRectangularWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "SlackRectangular", intent: StationConfigIntent.self,
                               provider: StationProvider()) { entry in
            AccessoryWidgetView(entry: entry, family: .accessoryRectangular)
        }
        .configurationDisplayName("Slack Window")
        .description("Next event plus the workable window.")
        .supportedFamilies([.accessoryRectangular])
    }
}
