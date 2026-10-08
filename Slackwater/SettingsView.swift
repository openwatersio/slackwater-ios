// Slackwater — GPL v3. Units, slack threshold, integrations, and widgets.
import SwiftUI

struct SettingsView: View {
    /// Opens the tour's station directly — see `StationListView.replayTour`
    /// for why this cannot just arm-and-dismiss.
    var onReplayTour: (() -> Void)? = nil
    @AppStorage(unitsKey, store: AppGroup.defaults) private var units = heightUnits()
    @AppStorage(speedUnitKey, store: AppGroup.defaults) private var speedUnit = "kn"
    @AppStorage(AppGroup.slackWindowSpeedKey, store: AppGroup.defaults)
    private var slackWindowSpeed = defaultSlackThresholdKn
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var alerts = AlertRuleStore.shared
    @ObservedObject private var calendars = StationCalendarStore.shared
    @State private var settle: Task<Void, Never>?

    /// What the Calendar row says it is doing, from what is actually subscribed.
    private var calendarSummary: String {
        let on = calendars.subscriptions.map(\.stationID)
        if on.isEmpty {
            return String(localized: "Publish a station's tides or slack windows to your calendar", comment: "Settings calendar row when no place is subscribed.")
        }
        if on.count == 1, let name = StationItem.byId[on[0]]?.name {
            return name
        }
        return String(localized: "\(on.count) stations", comment: "Settings calendar subscription count; used when multiple places are subscribed or a single place name is unavailable.")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    section(String(localized: "Tide height", comment: "Settings section heading.")) {
                        Picker(
                            "Tide height units",
                            selection: Binding(
                                get: { units }, set: { UnitsCloud.shared.set($0, forKey: unitsKey) })
                        ) {
                            Text("Feet").tag("imperial")
                            Text("Meters").tag("metric")
                        }
                        .pickerStyle(.segmented)
                    }

                    section(String(localized: "Current speed", comment: "Settings section heading.")) {
                        Picker(
                            "Current speed units",
                            selection: Binding(
                                get: { speedUnit }, set: { UnitsCloud.shared.set($0, forKey: speedUnitKey) })
                        ) {
                            Text("Knots").tag("kn")
                            Text(verbatim: "km/h").tag("kmh")
                            Text(verbatim: "m/s").tag("ms")
                        }
                        .pickerStyle(.segmented)
                    }

                    section(String(localized: "Slack window", comment: "Settings section heading.")) {
                        Stepper(value: slackWindowSpeedBinding, in: 0.1...10, step: 0.1) {
                            HStack {
                                Text("Comfort current")
                                Spacer()
                                Text(
                                    slackWindowSpeedBinding.wrappedValue,
                                    format: .number.precision(.fractionLength(1))
                                )
                                .monospacedDigit()
                                Text(verbatim: "kn")
                            }
                        }
                        SlackWindowPreview(threshold: slackWindowSpeedBinding.wrappedValue)
                        Text("Sets the fastest current Slackwater treats as a usable slack window (0.1–10 kn).")
                    }

                    section(String(localized: "Alerts", comment: "Settings section heading.")) {
                        NavigationLink {
                            AlertsView()
                                .navigationTitle("Alerts")
                                .navigationBarTitleDisplayMode(.inline)
                                .toolbarBackground(SN.canvas, for: .navigationBar)
                        } label: {
                            HStack {
                                Text(
                                    alerts.rules.isEmpty
                                        ? "Press and hold any station's timeline to set an alert"
                                        : "\(alerts.rules.count) alerts")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                            }
                            .foregroundStyle(SN.leaf)
                        }
                    }

                    section(String(localized: "Calendar", comment: "Settings section heading.")) {
                        NavigationLink {
                            CalendarStationsView()
                                .navigationTitle("Favourites calendars")
                                .navigationBarTitleDisplayMode(.inline)
                                .toolbarBackground(SN.canvas, for: .navigationBar)
                        } label: {
                            HStack {
                                Text(calendarSummary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                            }
                            .foregroundStyle(SN.leaf)
                        }
                        .accessibilityIdentifier("settings-calendar-row")
                    }

                    if let onReplayTour {
                        section(String(localized: "How to read a station", comment: "Settings section heading.")) {
                            Button {
                                dismiss()
                                onReplayTour()
                            } label: {
                                HStack {
                                    Text(
                                        "Show the tour again",
                                        comment: "Settings row that replays the first-run tour.")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                }
                            }
                            .accessibilityIdentifier("settings-replay-tour")
                        }

                    }

                    WidgetSettingsContent()

                    NavigationLink {
                        AboutView()
                    } label: {
                        HStack {
                            Text("About")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                        }
                        .foregroundStyle(SN.leaf)
                        .padding(16)
                        .background(SN.cardFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .accessibilityIdentifier("settings-about-row")

                }
                .padding(20)
                .padding(.bottom, 30)
            }
            .background(CanvasBackground())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(SN.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(SN.leaf)
                }
            }


        }
    }

    private var slackWindowSpeedBinding: Binding<Double> {
        Binding(
            get: { normalizedSlackThresholdKn(slackWindowSpeed) },
            set: {
                slackWindowSpeed = normalizedSlackThresholdKn($0)
                // Every scheduled slack window was computed at the old threshold — but only
                // the value the user stops on is worth rewriting them for. Holding the
                // stepper walks ~99 of them under auto-repeat, and each pass removes and
                // re-adds every window in every subscribed calendar, over CalDAV, at a
                // threshold nobody asked to keep. The same goes for iCloud.
                // ponytail: a fixed 400 ms settle on the one control that repeats. A shared
                // debouncer when a second control needs one.
                let value = slackWindowSpeed
                settle?.cancel()
                settle = Task {
                    guard (try? await Task.sleep(for: .milliseconds(400))) != nil else { return }
                    UnitsCloud.shared.set(value, forKey: AppGroup.slackWindowSpeedKey)
                    // Redraws the widgets, which draw the window too, and reschedules alerts.
                    WidgetReload.trigger()
                }
            })
    }

    @ViewBuilder private func section(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel(text: label)
            content()
                .font(.footnote)
                .lineSpacing(3)
                .foregroundStyle(SN.foam.opacity(0.62))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(SN.cardFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(SN.cardStroke, lineWidth: 0.5))
    }
}
