// Slackwater — GPL v3. M4 settings: units (the same @AppStorage the list's
// pill toggles), boat-specific slack speed, the not-for-navigation statement,
// attribution & licenses, version.
import SwiftUI

struct SettingsView: View {
    @AppStorage(unitsKey, store: AppGroup.defaults) private var units = "imperial"
    @AppStorage(speedUnitKey, store: AppGroup.defaults) private var speedUnit = "kn"
    @AppStorage(AppGroup.slackWindowSpeedKey, store: AppGroup.defaults)
    private var slackWindowSpeed = defaultSlackThresholdKn
    @ObservedObject private var chs = ChsFitService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showPremium = false
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
                    section("Tide height") {
                        Picker("Tide height units", selection: $units) {
                            Text("Feet").tag("imperial")
                            Text("Meters").tag("metric")
                        }
                        .pickerStyle(.segmented)
                    }

                    section("Current speed") {
                        Picker("Current speed units", selection: $speedUnit) {
                            Text("Knots").tag("kn")
                            Text("km/h").tag("kmh")
                            Text("m/s").tag("ms")
                        }
                        .pickerStyle(.segmented)
                    }

                    section("Slack window") {
                        Stepper(value: slackWindowSpeedBinding, in: 0.1...10, step: 0.1) {
                            HStack {
                                Text("Comfort current")
                                Spacer()
                                Text(slackWindowSpeedBinding.wrappedValue,
                                     format: .number.precision(.fractionLength(1)))
                                    .monospacedDigit()
                                Text("kn")
                            }
                        }
                        Text("0.1–10 kn. This changes when Slackwater marks a current as a usable slack window.")
                    }

                    // The downloads manager also lives one tap from the list,
                    // behind the status indicator beside this screen's gear.
                    section("Offline downloads") {
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

                    section("Slackwater Premium") {
                        Button { showPremium = true } label: {
                            HStack {
                                Text(PremiumStore.shared.isPremium
                                     ? "Premium — thank you for supporting the app"
                                     : "Support the app — lock screen widgets and more")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                            }
                            .foregroundStyle(SN.leaf)
                        }
                        Button { showWidgets = true } label: {
                            HStack {
                                Text("Widgets — add them to your home and lock screen")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                            }
                            .foregroundStyle(SN.leaf)
                        }
                    }

                    section("About these predictions") {
                        Text("Slackwater computes harmonic tide and current predictions on this device. Predictions are not observations — actual conditions vary with weather, river flow and local effects.")
                        Text("Not for navigation.")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(SN.foam.opacity(0.9))
                        Text("Canadian (CHS) stations are harmonic models fitted on this device from CHS (IWLS) predictions fetched under DFO's terms — not CHS-published numbers. CHS data is used under licence (clause 10) and is not to be used for navigation. A few Canadian waters CHS does not gauge are covered by bundled TICON-4 constants instead.")
                    }

                    section("Data & attribution") {
                        Text("US stations: NOAA CO-OPS harmonic constituents (public domain).")
                        Text("Additional stations: TICON-4 harmonic constants, SEANOE — used under CC BY 4.0 (seanoe.org/data/00980/109129).")
                        Text("Map imagery: satellite tiles by VersaTiles (versatiles.org/sources), cached on this device for offline use.")
                        Text("Canadian channel bathymetry: GSC Canada West Coast Topo-Bathymetric DEM. Contains information licensed under the Open Government Licence – Canada.")
                        Text("US channel bathymetry: NOAA National Bathymetric Source (public domain).")
                        Text("Channel cross-sections for grown current patches are derived from this bathymetry; raw survey data is not included.")
                        Text("Station names & pairings: @sailingnaturali/station-corrections (MIT).")
                        Text("Prediction engine: slackwater-engine, a port of Neaps (MIT).")
                    }

                    section("License") {
                        Text("The Slackwater engine and web app are open source (MIT / GPL). This iOS app's own license is still being worked out — a copyleft structure that holds together with paid distribution — and will be published when it is.")
                    }

                    section("Version") {
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
            .sheet(isPresented: $showPremium) { PremiumView() }
            .sheet(isPresented: $showWidgets) { WidgetsGalleryView() }
        }
        .preferredColorScheme(.dark)
    }

    private var slackWindowSpeedBinding: Binding<Double> {
        Binding(get: { normalizedSlackThresholdKn(slackWindowSpeed) },
                set: { slackWindowSpeed = normalizedSlackThresholdKn($0) })
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
