// Slackwater — GPL v3. The matching-station chooser: one place, every station
// that answers for it.
import CoreLocation
import SwiftUI

/// One place and every station that answers for it.
struct StationMatches: Identifiable, Hashable {
    let place: String
    /// Nearest first; always includes the entry that opened the chooser.
    let matches: [StationItem]
    /// The station on screen for this place, selected when the chooser opens.
    var shown: String? = nil
    /// Set when the chooser is offering a replacement for a favorite whose
    /// station left the bundle (issue #91): the dead id to swap out, and the
    /// position the distances are measured from — where that station *was*,
    /// not where the user is. A dead Haida Gwaii favorite offering Victoria
    /// stations because that is where the phone happens to be is not an offer.
    /// A struct rather than the tuple it wants to be: tuples aren't Hashable,
    /// and this type is.
    struct Removed: Hashable {
        let id: String
        let lat: Double
        let lon: Double
    }
    var replacing: Removed? = nil
    var id: String { place }

    /// "2 other current locations": counts only the stations not on screen,
    /// short enough to share a row with the page's tide or current link.
    static func linkText(others: Int, series: StationSeries) -> String {
        "\(others) other \(series.rawValue) location\(others == 1 ? "" : "s")"
    }
}

/// The chooser's entry point on a station page, beside its tide or current
/// link (`StationLinksRow`). A pick is remembered for the list and widgets,
/// and opens on top of this page when it is a different station.
struct MatchingStationsLink: View {
    let item: StationItem
    @State private var place: StationMatches?
    @Environment(\.openStationItem) private var open

    var body: some View {
        if let namesakes = StationItem.byPlace[item.placeKey], namesakes.count > 1 {
            BranchLink(text: StationMatches.linkText(others: namesakes.count - 1, series: item.series),
                       id: "matching-stations", chevron: false) {
                let from = LocationService.shared.rankingAnchor
                place = StationMatches(place: item.name,
                                       matches: StationItem.rankedByDistance(namesakes, lat: from.lat, lon: from.lon),
                                       shown: item.id)
            }
            .sheet(item: $place) { place in
                let loc = LocationService.shared
                StationChooserSheet(place: place, anchor: loc.rankingAnchor,
                                    anchorName: loc.authorized && loc.location != nil ? "you" : nil) { picked in
                    ChosenStationsStore.shared.choose(picked)
                    if picked.id != item.id { open(picked) }
                }
            }
        }
    }
}

/// The matching-station chooser (web `StationChooser.tsx`, list-side): where
/// several stations of one series share a name, the list shows the nearest
/// and this offers the rest. Alternatives are optional, so it opens on the
/// shown station and explains the default instead of asking for a pick. A
/// map places every candidate; a pin selects its row, a row opens its station.
struct StationChooserSheet: View {
    let place: StationMatches
    let anchor: (lat: Double, lon: Double)
    /// Who or what `anchor` is, for "2.1 nm from you". Nil hides distances:
    /// measured from a last-opened station, they would read as from the user.
    let anchorName: String?
    let onPick: (StationItem) -> Void
    @State private var selected: String?
    /// Where each match lands on the map, in `place.matches` order.
    @State private var pinPoints: [CGPoint] = []
    @Environment(\.dismiss) private var dismiss

    init(place: StationMatches, anchor: (lat: Double, lon: Double), anchorName: String?,
         onPick: @escaping (StationItem) -> Void) {
        self.place = place
        self.anchor = anchor
        self.anchorName = anchorName
        self.onPick = onPick
        _selected = State(initialValue: place.shown)
    }

    var body: some View {
        ZStack {
            CanvasBackground()
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(place.place)
                            .font(.title.weight(.semibold))
                            .foregroundStyle(SN.paper)
                        Text(explanation)
                            .font(.footnote)
                            .foregroundStyle(SN.foam.opacity(0.62))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SN.foam.opacity(0.8))
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
                .padding(.horizontal, 22)
                .padding(.top, 24)
                .padding(.bottom, 16)

                if !place.matches.isEmpty {
                    map
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(SN.cardStroke, lineWidth: 0.5))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(place.matches) { row($0).id($0.id) }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                    // A nil anchor scrolls only as far as the row needs.
                    .onChange(of: selected) { _, id in
                        withAnimation { proxy.scrollTo(id) }
                    }
                }
            }
        }
        // Full height: the map and the rows under it need the room.
        .presentationDetents([.large])
        .accessibilityIdentifier("station-chooser")
    }

    private var explanation: String {
        if place.replacing != nil {
            return "These stations are nearest to where it was. Pick one to replace this favorite."
        }
        let review = "Review the other locations if you need predictions for a different part of the water."
        guard let shown = place.matches.first(where: { $0.id == place.shown }) else { return review }
        // "Closest" only holds when the distances are measured from a named point.
        let lead = anchorName != nil && shown.id == place.matches.first?.id
            ? "Slackwater is showing the closest station."
            : "Slackwater is showing \(shown.placeLabel)."
        return lead + " " + review
    }

    /// Pins are SwiftUI views over the map rather than map layers, so one
    /// view carries the tap, the selection ring, and the VoiceOver element.
    private var map: some View {
        let lats = place.matches.map(\.latitude)
        let lons = place.matches.map(\.longitude)
        // Centred on the matches' bounds, so framing them fits exactly those bounds.
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2,
                                            longitude: (lons.min()! + lons.max()!) / 2)
        return MapViewRepresentable(center: center,
                                    framing: place.matches.map {
                                        CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                                    },
                                    onSelect: { _ in },
                                    onProject: { pinPoints = $0 })
            .overlay(alignment: .topLeading) {
                ForEach(pinPoints.indices, id: \.self) { i in
                    pin(place.matches[i]).position(pinPoints[i])
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("chooser-map")
    }

    private func pin(_ item: StationItem) -> some View {
        let isSelected = item.id == selected
        let shape = item.series == .tide ? AnyShape(Rectangle()) : AnyShape(Circle())
        return Button { selected = item.id } label: {
            ZStack {
                if isSelected {
                    Circle().strokeBorder(SN.leaf, lineWidth: 2.5).frame(width: 26, height: 26)
                }
                shape.fill(SN.paper)
                    .overlay(shape.stroke(SN.canvas, lineWidth: 1.5))
                    .frame(width: 10, height: 10)
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spoken(item))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("chooser-pin")
    }

    private func row(_ item: StationItem) -> some View {
        Button {
            onPick(item)
            dismiss()
        } label: {
            StationChoiceRow(title: item.placeLabel,
                             caption: item.kindLabel,
                             distance: distance(item),
                             note: item.id == place.shown ? "Shown" : nil,
                             selected: item.id == selected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(item.id == selected ? .isSelected : [])
        .accessibilityIdentifier("chooser-station")
    }

    /// "2.1 nm from you", or empty without an `anchorName`.
    private func distance(_ item: StationItem) -> String {
        guard let anchorName else { return "" }
        return "\(formatNm(item.km(fromLat: anchor.lat, lon: anchor.lon))) from \(anchorName)"
    }

    private func spoken(_ item: StationItem) -> String {
        [item.placeLabel, distance(item), item.id == place.shown ? "currently shown" : ""]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

/// A station row's face: a title, what it measures, and how far — the
/// chooser's rows and a detail's Nearby rows. Callers own the tap.
struct StationChoiceRow: View {
    let title: String
    let caption: String
    let distance: String
    /// A leaf mark after the caption, such as the chooser's "Shown".
    var note: String? = nil
    var selected = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(SN.paper)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 8) {
                    MonoLabel(text: caption, color: SN.foam.opacity(0.55), tracking: 1.1)
                    if let note { MonoLabel(text: note, tracking: 1.1) }
                }
            }
            Spacer(minLength: 8)
            Text(distance)
                .font(.caption.monospaced().weight(.medium))
                .foregroundStyle(SN.foam.opacity(0.85))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(selected ? 0.1 : 0.05),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(selected ? SN.leaf : SN.leaf.opacity(0.16), lineWidth: selected ? 1.5 : 0.5))
        .contentShape(Rectangle())
    }
}
