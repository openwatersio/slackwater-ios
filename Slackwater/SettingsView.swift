// Slackwater — GPL v3. M4 settings: units (the same @AppStorage the list's
// pill toggles), boat-specific slack speed, the not-for-navigation statement,
// attribution & licenses, version.
import SwiftUI

struct SettingsView: View {
    /// Opens the tour's station directly — see `StationListView.replayTour`
    /// for why this cannot just arm-and-dismiss.
    let onReplayTour: () -> Void
    @AppStorage(unitsKey, store: AppGroup.defaults) private var units = "imperial"
    @AppStorage(speedUnitKey, store: AppGroup.defaults) private var speedUnit = "kn"
    @AppStorage(AppGroup.slackWindowSpeedKey, store: AppGroup.defaults)
    private var slackWindowSpeed = defaultSlackThresholdKn
    @ObservedObject private var chs = ChsFitService.shared
    #if PREMIUM_ENABLED
    @ObservedObject private var premium = PremiumStore.shared
    @State private var showPremium = false
    #endif
    @Environment(\.dismiss) private var dismiss
    @State private var showWidgets = false

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    section(String(localized: "Tide height", comment: "Settings section heading.")) {
                        Picker("Tide height units", selection: Binding(
                            get: { units }, set: { UnitsCloud.shared.set($0, forKey: unitsKey) })) {
                            Text("Feet").tag("imperial")
                            Text("Meters").tag("metric")
                        }
                        .pickerStyle(.segmented)
                    }

                    section(String(localized: "Current speed", comment: "Settings section heading.")) {
                        Picker("Current speed units", selection: Binding(
                            get: { speedUnit }, set: { UnitsCloud.shared.set($0, forKey: speedUnitKey) })) {
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
                                Text(slackWindowSpeedBinding.wrappedValue,
                                     format: .number.precision(.fractionLength(1)))
                                    .monospacedDigit()
                                Text(verbatim: "kn")
                            }
                        }
                        Text("Sets the fastest current Slackwater treats as a usable slack window (0.1–10 kn).")
                    }

                    // The downloads manager also lives one tap from the list,
                    // behind the status indicator beside this screen's gear.
                    section(String(localized: "Offline downloads", comment: "Settings section heading.")) {
                        NavigationLink {
                            OfflineManagerList()
                                .navigationTitle("Downloads")
                                .navigationBarTitleDisplayMode(.inline)
                                .toolbarBackground(SN.canvas, for: .navigationBar)
                        } label: {
                            HStack {
                                Text("\(chs.queue.ready) of \(chs.queue.total) nearby Canadian stations on this device")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                            }
                            .foregroundStyle(SN.leaf)
                        }
                    }

                    section(String(localized: "How to read a station", comment: "Settings section heading.")) {
                        Button {
                            dismiss()
                            onReplayTour()
                        } label: {
                            HStack {
                                Text("Show the tour again", comment: "Settings row that replays the first-run tour.")
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                        }
                        .accessibilityIdentifier("settings-replay-tour")
                    }

                    #if PREMIUM_ENABLED
                    section(String(localized: "Slackwater Premium", comment: "Settings section heading.")) {
                        Button { showPremium = true } label: {
                            HStack {
                                Text(premium.isPremium
                                     ? String(localized: "Premium — thank you for supporting the app", comment: "Premium settings row for an existing supporter.")
                                     : String(localized: "Support the app — lock screen widgets and more", comment: "Premium settings row for a non-subscriber."))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                            }
                            .foregroundStyle(SN.leaf)
                        }
                        widgetsButton(String(localized: "Widgets — add them to your home and lock screen", comment: "Settings link to the widget gallery."))
                    }
                    #else
                    section(String(localized: "Widgets", comment: "Settings section heading.")) {
                        widgetsButton(String(localized: "Widgets — add them to your home screen", comment: "Settings link to the widget gallery."))
                    }
                    #endif

                    section(String(localized: "About these predictions", comment: "Settings section heading.")) {
                        Text("Slackwater computes harmonic tide and current predictions on this device. They are not observations; actual conditions vary with weather, river flow, and local effects.")
                        Text("Not for navigation.")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(SN.foam.opacity(0.9))
                        Text("Canadian (CHS) stations use harmonic models fitted on this device from CHS (IWLS) predictions under DFO's terms (clause 10). They are not CHS-published numbers and are not for navigation. A few Canadian waters without CHS gauges use bundled TICON-4 constants.")
                    }

                    section(String(localized: "Data & attribution", comment: "Settings section heading.")) {
                        Text("US stations: NOAA CO-OPS harmonic constituents (public domain).")
                        Text("Additional stations use TICON-4 harmonic constants from SEANOE under CC BY 4.0 (seanoe.org/data/00980/109129).")
                        // Issue #401. The same deposit also holds a
                        // cc-by-nc-4.0 half (GESLA upstream restricts
                        // commercial use) whose CONSTANTS can never ship —
                        // and the map now names 139 of those stations, so
                        // the credits screen has to account for what it is
                        // showing. Identity only: a name, a region and a
                        // position we display to explain an absence, which
                        // is not a use of the predictions the licence
                        // covers. The attribution is owed either way.
                        Text("Stations marked \"Predictions unavailable\" are named from non-commercial records in the same SEANOE deposit (CC BY-NC 4.0). Slackwater does not bundle or serve their harmonic constants.")
                        Text("Map tiles by OpenFreeMap (openfreemap.org), © OpenMapTiles, data © OpenStreetMap contributors, cached on this device for offline use.")
                        Text("Canadian channel bathymetry: GSC Canada West Coast Topo-Bathymetric DEM. Contains information licensed under the Open Government Licence – Canada.")
                        Text("US channel bathymetry: NOAA National Bathymetric Source (public domain).")
                        Text("Channel cross-sections for grown current patches are derived from this bathymetry; raw survey data is not included.")
                        Text("Station names and pairings: Slackwater database (MIT).")
                        Text("Prediction engine: Slackwater (MIT).")
                    }

                    section(String(localized: "Privacy", comment: "Settings section heading.")) {
                        Link("Privacy Policy", destination: URL(string: "https://slackwater.xyz/privacy")!)
                            .foregroundStyle(SN.leaf)
                    }

                    section(String(localized: "License", comment: "Settings section heading.")) {
                        Text("Slackwater is open source: this app under GPL-3.0, the prediction engine under MIT.")
                        Link("Source on GitHub", destination: URL(string: "https://github.com/openwatersio/slackwater-ios")!)
                            .foregroundStyle(SN.leaf)
                    }

                    section(String(localized: "Version", comment: "Settings section heading.")) {
                        Text(version)
                            .font(.footnote.monospaced())
                            .foregroundStyle(SN.foam.opacity(0.7))
                    }
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
            #if PREMIUM_ENABLED
            .sheet(isPresented: $showPremium) { PremiumView() }
            #endif
            .sheet(isPresented: $showWidgets) { WidgetsGalleryView() }
        }
    }

    private var slackWindowSpeedBinding: Binding<Double> {
        Binding(get: { normalizedSlackThresholdKn(slackWindowSpeed) },
                set: {
                    slackWindowSpeed = normalizedSlackThresholdKn($0)
                    // Every scheduled slack window was computed at the old threshold.
                    AlertScheduler.requestReschedule()
                })
    }

    private func widgetsButton(_ title: String) -> some View {
        Button { showWidgets = true } label: {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
            }
            .foregroundStyle(SN.leaf)
        }
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
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(SN.cardStroke, lineWidth: 0.5))
    }
}
