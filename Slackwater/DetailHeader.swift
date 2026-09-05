// Slackwater — GPL v3. The detail-view header: the station name in large type
// over its region. Back / favorite chrome sits above in fixed 44pt glass
// circles; the readings live in the scrub card below.
import SwiftUI

struct DetailHeader: View {
    let name: String
    let region: String
    /// StationItem id this detail shows — the favorite star toggles it.
    let favoriteId: String
    /// The real top safe-area inset, read by the caller's GeometryReader.
    /// Every detail puts `.ignoresSafeArea(edges: .top)` on its ScrollView,
    /// which also strips the implicit system padding — the header supplies its
    /// own clearance, and it must be the device's actual inset (issue #50).
    let topSafeInset: CGFloat
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openMapFocused) private var openMapFocused
    @ObservedObject private var favorites = FavoritesStore.shared
    @ObservedObject private var location = LocationService.shared

    /// "Puget Sound • 3.2 nm" when there is a fix; just the region otherwise.
    /// Distance is from the fix to the station.
    private var regionLine: String {
        guard location.authorized, let fix = location.location,
              let item = StationItem.byId[favoriteId] else { return region }
        let km = item.km(fromLat: fix.coordinate.latitude, lon: fix.coordinate.longitude)
        return "\(region) • \(formatNm(km))"
    }

    var body: some View {
        VStack(spacing: 8) {
            // Back / star: fixed 44pt circles, deliberately not scaled with
            // Dynamic Type — chrome in fixed-size hit targets, not text
            // companions (the wordmark's comment in SlackwaterApp.swift has
            // the 320pt iPad sidebar story).
            GlassEffectContainer {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .glassEffect(.regular.interactive(), in: Circle())
                    }
                    .accessibilityLabel("Back")
                    .accessibilityIdentifier("detail-back")
                    Spacer()
                    let fav = favorites.contains(favoriteId)
                    Button { favorites.toggle(favoriteId) } label: {
                        Image(systemName: fav ? "star.fill" : "star")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(fav ? SN.sun : .white)
                            .frame(width: 44, height: 44)
                            .glassEffect(.regular.interactive(), in: Circle())
                    }
                    .accessibilityLabel(fav ? "Remove favorite" : "Add favorite")
                    .accessibilityIdentifier("detail-favorite")
                }
            }

            VStack(spacing: 2) {
                Text(name)
                    .font(.title)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(regionLine)
                    .font(.caption)
                    .foregroundStyle(SN.foam.opacity(0.55))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                // Jump to the discovery map, focused on this station (#32). A
                // catalog miss is a no-op, not a crash.
                if let item = StationItem.byId[favoriteId] { openMapFocused(item) }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("detail-title")
        }
        .padding(.horizontal, 16)
        .padding(.top, topSafeInset)
        .padding(.bottom, 16)
        // Every scrub detail is built on this header, so arming the edge-swipe
        // here arms it for all four.
        .background(InteractivePopEnabler())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail-header")
    }
}
