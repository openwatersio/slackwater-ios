// Slackwater — GPL v3. Prediction notes, attribution, privacy, and app information.
import SwiftUI

struct AboutView: View {
    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                section(String(localized: "About these predictions", comment: "Settings section heading.")) {
                    Text(
                        "Slackwater computes harmonic tide and current predictions on this device. They are not observations; actual conditions vary with weather, river flow, and local effects."
                    )
                    Text("Not for navigation.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(SN.foam.opacity(0.9))
                    Text(
                        "Canadian (CHS) stations use harmonic models fitted on this device from CHS (IWLS) predictions under DFO's terms (clause 10). They are not CHS-published numbers and are not for navigation. A few Canadian waters without CHS gauges use bundled TICON-4 constants."
                    )
                }

                section(String(localized: "Data & attribution", comment: "Settings section heading.")) {
                    Text("US stations: NOAA CO-OPS harmonic constituents (public domain).")
                    Text(
                        "Norwegian stations: harmonic constants © Kartverket (Norwegian Mapping Authority, Hydrographic Service) under CC BY 4.0 (kartverket.no)."
                    )
                    Text(
                        "Additional stations use TICON-4 harmonic constants from SEANOE under CC BY 4.0 (seanoe.org/data/00980/109129)."
                    )
                    // Issue #401. The same deposit also holds a
                    // cc-by-nc-4.0 half (GESLA upstream restricts
                    // commercial use) whose CONSTANTS can never ship —
                    // and the map now names 139 of those stations, so
                    // the credits screen has to account for what it is
                    // showing. Identity only: a name, a region and a
                    // position we display to explain an absence, which
                    // is not a use of the predictions the licence
                    // covers. The attribution is owed either way.
                    Text(
                        "Stations marked \"Predictions unavailable\" are named from non-commercial records in the same SEANOE deposit (CC BY-NC 4.0). Slackwater does not bundle or serve their harmonic constants."
                    )
                    Text(
                        "Map tiles by OpenFreeMap (openfreemap.org), © OpenMapTiles, data © OpenStreetMap contributors, cached on this device for offline use."
                    )
                    Text(
                        "Canadian channel bathymetry: GSC Canada West Coast Topo-Bathymetric DEM. Contains information licensed under the Open Government Licence – Canada."
                    )
                    Text("US channel bathymetry: NOAA National Bathymetric Source (public domain).")
                    Text(
                        "Channel cross-sections for grown current patches are derived from this bathymetry; raw survey data is not included."
                    )
                    Text("Station names and pairings: Slackwater database (MIT).")
                    Text("Prediction engine: Slackwater (MIT).")
                }

                section(String(localized: "Privacy", comment: "Settings section heading.")) {
                    Link("Privacy Policy", destination: URL(string: "https://slackwater.xyz/privacy")!)
                        .foregroundStyle(SN.leaf)
                }

                section(String(localized: "License", comment: "Settings section heading.")) {
                    Text("Slackwater is open source: this app under GPL-3.0, the prediction engine under MIT.")
                    Link(
                        "Source on GitHub", destination: URL(string: "https://github.com/openwatersio/slackwater-ios")!
                    )
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
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(SN.canvas, for: .navigationBar)
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
