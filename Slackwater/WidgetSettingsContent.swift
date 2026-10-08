// Slackwater — GPL v3. Free and Premium widgets, with previews and add instructions.
import SwiftUI

struct WidgetSettingsContent: View {
    var platform: SettingsPlatform = .current
    /// The card the free widgets draw when first added: the default station,
    /// resolved as the widget provider resolves it. Nil when nothing is
    /// downloaded, which leaves the rows below as the whole explanation.
    @State private var card: WidgetCard?

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            if platform != .tv {
                group(
                    platform == .mac
                        ? String(localized: "Desktop — free", comment: "Free desktop widgets on Mac.")
                        : String(localized: "Home screen — free", comment: "Settings widget section title."),
                    note: platform == .mac
                        ? String(
                            localized: "Control-click your desktop → Edit Widgets → Slackwater.",
                            comment: "Instructions for adding a Mac desktop widget.")
                        : String(
                            localized: "Long-press your home screen → + → Slackwater.",
                            comment: "Instructions for adding a home-screen widget."),
                    rows: [
                        (
                            String(localized: "Next Event", comment: "Widget name."), "square.grid.2x2",
                            String(
                                localized: "Now, which way it's going, and the next turn.",
                                comment: "Next Event widget description.")
                        ),
                        (
                            String(localized: "Today's Curve", comment: "Widget name."), "waveform.path.ecg",
                            String(
                                localized: "Today's curve with the next event.",
                                comment: "Today's Curve widget description.")
                        ),
                    ]
                ) {
                    if let card {
                        // The widgets' own content views at iPhone widget
                        // sizes, over the canvas their container paints.
                        preview(NextEventContentView(card: card)).frame(width: 170)
                        preview(DayCurveContentView(card: card)).frame(maxWidth: 364)
                    }
                }
            }
            #if PREMIUM_ENABLED
                if platform == .mobile {
                    group(
                        String(localized: "Lock screen — Premium", comment: "Settings widget section title."),
                        note: String(
                            localized:
                                "Long-press your lock screen → Customize → add Slackwater above or below the clock.",
                            comment: "Instructions for adding a lock-screen widget."),
                        rows: [
                            (
                                String(localized: "Next Slack (inline)", comment: "Widget name and family."),
                                "lock.iphone",
                                String(
                                    localized: "Above the clock: the next event and time.",
                                    comment: "Inline widget description.")
                            ),
                            (
                                String(localized: "Next Event (circular)", comment: "Widget name and family."),
                                "circle.dashed",
                                String(
                                    localized: "A glance: arrow and time.", comment: "Circular widget description.")
                            ),
                            (
                                String(localized: "Slack Window (rectangular)", comment: "Widget name and family."),
                                "rectangle.dashed",
                                String(
                                    localized: "Next event plus the workable window.",
                                    comment: "Rectangular widget description.")
                            ),
                        ], premium: true
                    ) {}
                }
            #endif
        }
        .task {
            guard platform != .tv else { return }
            card = await Task.detached {
                let id = WidgetStationLoader.resolvedStationID(WidgetStationLoader.defaultStationID())
                // The default is Current Location, so the prefix (and
                // its location mark) is the provider's for that entry.
                return WidgetStationLoader.loadRecord(id: id).map {
                    WidgetCard.build($0, now: .now, stationNamePrefix: "Current Location")
                }
            }.value
        }
    }

    private func preview(_ content: some View) -> some View {
        content
            .frame(height: 170)
            .background(SN.canvas)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ViewBuilder private func group(
        _ title: String, note: String,
        rows: [(String, String, String)], premium: Bool = false,
        @ViewBuilder previews: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if premium {
                Label {
                    MonoLabel(text: title)
                } icon: {
                    Image(systemName: "sparkles").foregroundStyle(SN.leaf)
                }
                // The trait goes on the Label, not its title: a Label is one
                // accessibility element and the title view's own traits are
                // not that element's.
                .accessibilityAddTraits(.isHeader)
            } else {
                MonoLabel(text: title, isHeader: true)
            }
            previews()
            ForEach(rows, id: \.0) { row in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: row.1).frame(width: 24).foregroundStyle(SN.leaf)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.0).font(.footnote.weight(.medium)).foregroundStyle(SN.foam.opacity(0.85))
                        Text(row.2).font(.caption).foregroundStyle(SN.foam.opacity(0.62))
                    }
                }
            }
            Text(note).font(.caption2).foregroundStyle(SN.foam.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(SN.cardFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(SN.cardStroke, lineWidth: 0.5))
    }
}
