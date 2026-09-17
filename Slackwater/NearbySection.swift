// Slackwater — GPL v3. The Nearby section closing every scrub detail: the
// closest stations as chooser-style rows, over a map framing them.
import CoreLocation
import SwiftUI

struct NearbySection: View {
    /// Where the rows are measured from, and the id excluded from them.
    private let lat: Double, lon: Double, originID: String
    /// The station this page is about — marked on the map, and focused when
    /// the map is tapped off a pin. Nil for an unavailable station (issue
    /// #401): it has a position but is deliberately not a `StationItem`, so
    /// there is no pin in this source to mark and nothing to focus.
    private let focus: StationItem?

    init(item: StationItem) {
        lat = item.latitude
        lon = item.longitude
        originID = item.id
        focus = item
    }

    /// The Nearby section on an unavailable station's page: the same rows and
    /// the same framed map, around a place that has no predictions of its own.
    init(unavailable: UnavailableStation) {
        lat = unavailable.latitude
        lon = unavailable.longitude
        originID = unavailable.id
        focus = nil
    }

    @AppStorage(seriesFilterKey) private var filter: StationSeries?
    /// Ranked on a filter change, not in `body`: the scaffold re-renders on
    /// every scrub frame, and ranking sorts the whole catalog.
    @State private var stations: [StationItem] = []
    @Environment(\.openStationItem) private var open
    @Environment(\.openMapFocused) private var openMapFocused

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                MonoLabel(text: "Nearby")
                Spacer(minLength: 8)
                SeriesFilterChips()
            }
            .padding(.horizontal, 10)
            ForEach(stations) { row($0) }
            if !stations.isEmpty {
                // `selected: focus` is this page's own station, marked the
                // same way the discovery map marks a pin-tap pick — one
                // treatment, one code path. Nil on an unavailable station's
                // page: its ring lives in the map's other source, which this
                // layer has no `selected` property for.
                MapViewRepresentable(center: CLLocationCoordinate2D(latitude: lat,
                                                                    longitude: lon),
                                     framing: stations.map(coordinate),
                                     onMiss: focus.map { f in { openMapFocused(f, $0) } },
                                     selected: focus.map(MapSelection.init),
                                     onSelect: open)
                    // The representable reads its camera once, in makeUIView.
                    .id(stations.map(\.id))
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(SN.cardStroke, lineWidth: 0.5))
                    .accessibilityIdentifier("nearby-map")
            }
        }
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nearby")
        .onChange(of: filter, initial: true) {
            stations = StationItem.nearby(lat: lat, lon: lon, excluding: originID,
                                          series: filter)
        }
    }

    private func row(_ near: StationItem) -> some View {
        let km = near.km(fromLat: lat, lon: lon)
        let bearing = bearingDeg(lat, lon, near.latitude, near.longitude)
        return StationChoiceRow(title: near.name,
                                caption: near.region.isEmpty ? near.kindLabel
                                    : "\(near.region) · \(near.kindLabel)",
                                distance: "\(formatNm(km)) \(compass16(bearing))")
            // Not a Button: press tracking goes dead below the strip in the
            // iPad split detail column (OpenTideDetailKey, Theme.swift).
            .onTapGesture { open(near) }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("nearby-station")
    }

    private func coordinate(_ station: StationItem) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: station.latitude, longitude: station.longitude)
    }
}
