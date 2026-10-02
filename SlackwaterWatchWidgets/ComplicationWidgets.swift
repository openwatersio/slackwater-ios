// Slackwater — GPL v3. The watch's complications (#524), Premium only like
// the phone's lock-screen widgets: without the entitlement each draws the
// locked wave, and a tap opens the app.
import SwiftUI
import WidgetKit

@main
struct SlackwaterWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        #if PREMIUM_ENABLED
        InlineComplication()
        CircularComplication()
        CornerComplication()
        RectangularComplication()
        #endif
    }
}

struct InlineComplication: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "WatchInline", intent: StationConfigIntent.self,
                               provider: ComplicationProvider()) { entry in
            InlineView(entry: entry).widgetURL(accessoryDeepLink(entry))
        }
        .configurationDisplayName("Tide or Current")
        .description("The water now and which way it's going.")
        .supportedFamilies([.accessoryInline])
    }
}

struct CircularComplication: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "WatchCircular", intent: StationConfigIntent.self,
                               provider: ComplicationProvider()) { entry in
            CircularView(entry: entry).widgetURL(accessoryDeepLink(entry))
        }
        .configurationDisplayName("Tide or Current")
        .description("The line around now, with the water's height or speed.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct CornerComplication: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "WatchCorner", intent: StationConfigIntent.self,
                               provider: ComplicationProvider()) { entry in
            CornerView(entry: entry).widgetURL(accessoryDeepLink(entry))
        }
        .configurationDisplayName("Tide or Current")
        .description("Between low and high, or on the way to slack.")
        .supportedFamilies([.accessoryCorner])
    }
}

struct RectangularComplication: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "WatchRectangular", intent: StationConfigIntent.self,
                               provider: ComplicationProvider()) { entry in
            RectangularView(entry: entry).widgetURL(accessoryDeepLink(entry))
        }
        .configurationDisplayName("Tide or Current")
        .description("The place's curve, its turns and their times.")
        // card families
        .supportedFamilies([.accessoryRectangular])
    }
}
