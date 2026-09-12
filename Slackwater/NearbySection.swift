// Slackwater — GPL v3. The Nearby section closing every scrub detail: the
// closest stations as chooser-style rows, over a map framing them.
import CoreLocation
import SwiftUI

struct NearbySection: View {
    let item: StationItem
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
                MapViewRepresentable(center: coordinate(item),
                                     framing: stations.map(coordinate),
                                     onMiss: { openMapFocused(item, $0) },
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
            stations = StationItem.nearby(item, series: filter)
        }
    }

    private func row(_ near: StationItem) -> some View {
        let km = near.km(fromLat: item.latitude, lon: item.longitude)
        let bearing = bearingDeg(item.latitude, item.longitude, near.latitude, near.longitude)
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
