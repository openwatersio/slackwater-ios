// Slackwater — GPL v3. Units, slack threshold, the Premium card, and About.
import SwiftUI

struct SettingsView: View {
    /// Opens the tour's station directly — see `StationListView.replayTour`
    /// for why this cannot just arm-and-dismiss.
    var onReplayTour: (() -> Void)? = nil
    @AppStorage(unitsKey, store: AppGroup.defaults) private var units = heightUnits()
    @AppStorage(speedUnitKey, store: AppGroup.defaults) private var speedUnit = "kn"
    @AppStorage(setFormatKey, store: AppGroup.defaults) private var setFormat = "compass"
    @AppStorage(AppGroup.slackWindowSpeedKey, store: AppGroup.defaults)
    private var slackWindowSpeed = defaultSlackThresholdKn
    @AppStorage(AppGroup.skyBodiesKey, store: AppGroup.defaults) private var skyBodies = true
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var alerts = AlertRuleStore.shared
    @ObservedObject private var calendars = StationCalendarStore.shared
    @ObservedObject private var premium = PremiumStore.shared
    @State private var premiumFeature: PremiumFeature?
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
                    section(String(localized: "Tides", comment: "Tide category, filter, or height-unit heading.")) {
                        row(String(localized: "Height", comment: "Settings row label: the unit tide heights are written in.")) {
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
                    }

                    section(String(localized: "Currents", comment: "Current category, filter, or speed-unit heading.")) {
                        row(String(localized: "Speed", comment: "Settings row label: the unit current speeds are written in.")) {
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
                        row(String(localized: "Direction", comment: "Settings row label: how a current's set (the direction it flows toward) is written.")) {
                            Picker(
                                "Current direction format",
                                selection: Binding(
                                    get: { setFormat }, set: { UnitsCloud.shared.set($0, forKey: setFormatKey) })
                            ) {
                                Text("Compass").tag("compass")
                                Text("Degrees °T").tag("degrees")
                            }
                            .pickerStyle(.segmented)
                        }
                        row(String(localized: "Slack window", comment: "An alert's title when a slack window opens, and the Settings row for the comfort current.")) {
                            Stepper(value: slackWindowSpeedBinding, in: slackThresholdRange, step: 0.1) {
                                HStack {
                                    Text("Comfort current")
                                    Spacer()
                                    if slackWindowIsOff(slackWindowSpeedBinding.wrappedValue) {
                                        Text("Off", comment: "Comfort-current setting at zero: no slack window, only slack.")
                                    } else {
                                        Text(
                                            slackWindowSpeedBinding.wrappedValue,
                                            format: .number.precision(.fractionLength(1))
                                        )
                                        .monospacedDigit()
                                        Text(verbatim: "kn")
                                    }
                                }
                            }
                            SlackWindowPreview(threshold: slackWindowSpeedBinding.wrappedValue)
                            Text("Sets the fastest current Slackwater treats as a usable slack window (0.1–10 kn). Off shows only slack.")
                        }
                    }

                    // The Premium features Settings has a say in, one card, a row each like the
                    // free widget rows. The Premium sheet does the selling; this card only names and controls.
                    section(String(localized: "Slackwater Premium"), premium: true) {
                        premiumRow(.sky) {
                            Toggle(isOn: Binding(
                                get: { skyBodies },
                                set: { on in
                                    // A refused change leaves the switch where it was: the getter still reads the stored value.
                                    guard skyBodiesSwitchAllowed(to: on, premium: premium.isPremium) else {
                                        premiumFeature = .sky
                                        return
                                    }
                                    UnitsCloud.shared.set(on, forKey: AppGroup.skyBodiesKey)
                                })
                            ) {
                                Text("Sun, moon and stars", comment: "Settings switch: draw the sun, moon and stars in the sky above the chart.")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(SN.foam.opacity(0.85))
                            }
                            .tint(SN.leaf)
                            .accessibilityIdentifier("settings-sky-bodies")
                            Text("Draw them in the sky above the chart as they stand at the selected time, and mark sunrise and sunset under each day. Off keeps the sky's day and night colors.", comment: "Settings footnote under the sun, moon and stars switch.")
                        }
                        Divider()
                        premiumRow(.alerts) {
                            NavigationLink {
                                AlertsView()
                                    .navigationTitle("Alerts")
                                    .navigationBarTitleDisplayMode(.inline)
                                    .toolbarBackground(SN.canvas, for: .navigationBar)
                            } label: {
                                HStack {
                                    Text(
                                        alerts.rules.isEmpty
                                            ? "Tap Set an alert under any station's timeline"
                                            : "\(alerts.rules.count) alerts")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.footnote.weight(.semibold))
                                }
                                .foregroundStyle(SN.leaf)
                            }
                        }
                        Divider()
                        premiumRow(.calendars) {
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
                        #if PREMIUM_ENABLED
                            // A build without PREMIUM_ENABLED ships no lock screen widgets.
                            if SettingsPlatform.current == .mobile {
                                Divider()
                                premiumRow(.lockScreen) {
                                    Text(PremiumFeature.lockScreen.detail)
                                    Text("Long-press your lock screen → Customize → add Slackwater above or below the clock.")
                                        .font(.caption)
                                }
                            }
                            if premium.hasPurchased {
                                // Thanks, not another sale; still a way to the sheet, which
                                // holds the free widgets' add instructions.
                                Button { premiumFeature = .lockScreen } label: {
                                    Label("You have Premium — thank you.", systemImage: "sparkles")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(SN.leaf)
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("settings-premium-cta")
                            } else {
                                // The sheet opens on the card's last row where there is one; the
                                // carousel falls back to its first page on a Mac or TV.
                                Button { premiumFeature = .lockScreen } label: {
                                    Label(String(localized: "Support Slackwater"), systemImage: "sparkles")
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(SN.leaf)
                                .foregroundStyle(SN.canvas)
                                .accessibilityIdentifier("settings-premium-cta")
                            }
                        #endif
                    }

                    #if !PREMIUM_ENABLED
                        // Nothing in this build sells Premium, so the sheet does not show the
                        // free widgets and Settings keeps them.
                        WidgetSettingsContent()
                    #endif

                    section(String(localized: "About")) {
                        Link(destination: URL(string: "https://slackwater.xyz/support/")!) {
                            HStack {
                                Text("Help").font(.headline).foregroundStyle(SN.leaf)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                            }
                            .frame(minHeight: 44)
                        }
                        .accessibilityIdentifier("settings-help")
                        Divider()
                        if let onReplayTour {
                            Button {
                                dismiss()
                                onReplayTour()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("How to read a station").font(.headline).foregroundStyle(SN.leaf)
                                        Text("Show the tour again").font(.footnote)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                }
                                .frame(minHeight: 44)
                            }
                            .accessibilityIdentifier("settings-replay-tour")
                            Divider()
                        }
                        NavigationLink {
                            AboutView()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("About").font(.headline).foregroundStyle(SN.leaf)
                                    Text("Licensing, acknowledgements, and privacy")
                                        .font(.footnote)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .frame(minHeight: 44)
                        }
                        .accessibilityIdentifier("settings-about-row")
                    }

                }
                .padding(20)
                .padding(.bottom, 30)
            }
            .background(CanvasBackground())
            .sheet(item: $premiumFeature) { PremiumView(opening: $0) }
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
                // iCloud takes every step, so the device and cloud copies never disagree
                // and an unrelated change arriving mid-hold cannot pull the stepper back.
                UnitsCloud.shared.set(normalizedSlackThresholdKn($0),
                                      forKey: AppGroup.slackWindowSpeedKey, reloading: false)
                // Every scheduled slack window was computed at the old threshold — but only
                // the value the user stops on is worth rewriting them for. Holding the
                // stepper walks ~99 of them under auto-repeat, and each pass removes and
                // re-adds every window in every subscribed calendar, over CalDAV, at a
                // threshold nobody asked to keep.
                // ponytail: a fixed 400 ms settle on the one control that repeats. A shared
                // debouncer when a second control needs one.
                settle?.cancel()
                settle = Task {
                    guard (try? await Task.sleep(for: .milliseconds(400))) != nil else { return }
                    // Redraws the widgets, which draw the window too, and reschedules alerts.
                    WidgetReload.trigger()
                }
            })
    }

    /// One setting inside a section: its label over its control.
    @ViewBuilder private func row(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(SN.foam.opacity(0.85))
            content()
        }
        .padding(.top, 4)
    }

    /// One Premium feature inside the Premium card: the sheet's symbol and title, then its control.
    @ViewBuilder private func premiumRow(_ feature: PremiumFeature, @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: feature.symbol).frame(width: 24).foregroundStyle(SN.leaf)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(feature.title)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(SN.foam.opacity(0.85))
                content()
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder private func section(_ label: String, premium: Bool = false, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                MonoLabel(text: label, isHeader: true)
                if premium {
                    Image(systemName: "sparkles")
                        .foregroundStyle(SN.leaf)
                        .accessibilityLabel("Premium")
                }
            }
            content()
                .font(.footnote)
                .multilineTextAlignment(.leading)
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
