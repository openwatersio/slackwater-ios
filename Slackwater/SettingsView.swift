// Slackwater — GPL v3. M4 settings: units (the same @AppStorage the list's
// pill toggles), the not-for-navigation statement, attribution & licenses,
// version. Nothing speculative — slack limit is the paid tier's, sold rather
// than missing (web Settings.tsx note).
import SwiftUI

struct SettingsView: View {
    @AppStorage(unitsKey) private var units = "imperial"
    @AppStorage(speedUnitKey) private var speedUnit = "kn"
    @Environment(\.dismiss) private var dismiss

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

                    section("About these predictions") {
                        Text("Slackwater computes harmonic tide and current predictions on this device. Predictions are not observations — actual conditions vary with weather, river flow and local effects.")
                        Text("Not for navigation.")
                            .font(.geist(13, .semibold))
                            .foregroundStyle(SN.foam.opacity(0.9))
                        Text("Canadian (CHS) stations are harmonic models fitted on this device from CHS (IWLS) predictions fetched under DFO's terms — not CHS-published numbers. CHS data is used under licence (clause 10) and is not to be used for navigation.")
                    }

                    section("Data & attribution") {
                        Text("US stations: NOAA CO-OPS harmonic constituents (public domain).")
                        Text("Map land layer: © OpenStreetMap contributors (ODbL).")
                        Text("Map bathymetry: Seascape © Open Water Software, LLC (CC BY 4.0), when online.")
                        Text("Station names & pairings: @sailingnaturali/station-corrections (MIT).")
                        Text("Prediction engine: slackwater-engine, a port of Neaps (MIT).")
                        Text("Fonts: Fraunces, Geist and Geist Mono, used under the SIL Open Font License 1.1.")
                    }

                    section("License") {
                        Text("The Slackwater engine and web app are open source (MIT / GPL). This iOS app's own license is still being worked out — a copyleft structure that holds together with paid distribution — and will be published when it is.")
                    }

                    section("Version") {
                        Text(version)
                            .font(.geistMono(14))
                            .foregroundStyle(SN.foam.opacity(0.7))
                    }
                }
                .padding(20)
                .padding(.bottom, 30)
            }
            .background(SN.page.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(SN.page, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(SN.leaf)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private func section(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel(text: label)
            content()
                .font(.geist(14))
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
