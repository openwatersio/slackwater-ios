// Slackwater — GPL v3. The matching-station chooser: one place, every station
// that answers for it.
import SwiftUI

/// One place and every station that answers for it.
struct StationMatches: Identifiable, Hashable {
    let place: String
    /// Nearest first; always includes the entry that opened the chooser.
    let matches: [StationItem]
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
}

/// The matching-station chooser (web `StationChooser.tsx`, list-side): where
/// several stations share a name, the list shows the nearest and this says so
/// rather than silently hiding the rest. Each row carries the two things that
/// aren't the name — what it measures (tide or current, NOAA or CHS) and how
/// far it is — so the pick is informed rather than a guess between identical
/// labels.
struct StationChooserSheet: View {
    let place: StationMatches
    let anchor: (lat: Double, lon: Double)
    let onPick: (StationItem) -> Void
    @Environment(\.dismiss) private var dismiss
    // Glyph-in-slot sizing (issue #14): the glyph
    // scales with type, the slot scales with it so it can't overflow the row.

    var body: some View {
        ZStack {
            CanvasBackground()
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(place.place)
                            .font(.title.weight(.semibold))
                            .foregroundStyle(SN.paper)
                        Text("\(place.matches.count) stations answer for this place — pick the one you mean.")
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

                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(place.matches) { row($0) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("station-chooser")
    }

    private func row(_ item: StationItem) -> some View {
        Button {
            onPick(item)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    // The name is the same on every row — the qualifier is the
                    // whole point, so it leads.
                    Text(item.region.isEmpty ? item.name : item.region)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(SN.paper)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    MonoLabel(text: item.kindLabel,
                              color: SN.foam.opacity(0.55), tracking: 1.1)
                }
                Spacer(minLength: 8)
                Text(formatNm(item.km(fromLat: anchor.lat, lon: anchor.lon)))
                    .font(.caption.monospaced().weight(.medium))
                    .foregroundStyle(SN.foam.opacity(0.85))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(SN.leaf.opacity(0.16), lineWidth: 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
