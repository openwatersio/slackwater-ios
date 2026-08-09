// Slackwater — GPL v3. The detail-view map header (map-hero spec §1/§2, header
// portion only — no particle field, no universal scrub yet): the station's map
// is the hero surface, scrim-darkened so the overlaid title reads (spec §5a/§7
// legibility risk), with the prototype's back / title-pill chrome
// (TidesApp.dc.html detail hero). Cropped to intrinsic height — pill +
// clearances — per the hero-crop-and-scrub-order spec (2026-08-03); return-to-now
// lives in the scrub card's readout row now (ReturnToNowSlot, Theme.swift).
import SwiftUI
import UIKit
import MapLibre

/// Bottom band of map kept below the title pill — the border the name sits
/// on, not a viewport. The header's height is pill + clearances, so it
/// scales with Dynamic Type instead of cropping at AX sizes.
let mapHeaderBottomMargin: CGFloat = 24
/// Prototype per-station zoom (DATA() z: 12.2–13.2). Not `private`: the
/// header title tap (issue #32) reuses it as the discovery map's focus zoom
/// so a jump-to-map lands at the same per-station framing this header shows,
/// rather than a second hand-picked number drifting from this one.
let stationZoom = 12.5

struct MapHeader: View {
    let name: String
    let region: String
    let latitude: Double
    let longitude: Double
    /// StationItem id this detail shows — the favorite star toggles it.
    let favoriteId: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openMapFocused) private var openMapFocused
    @ObservedObject private var favorites = FavoritesStore.shared

    var body: some View {
        // Back / star: fixed 44pt circles, deliberately not scaled with
        // Dynamic Type (unlike Task 5's inline-with-text symbols). These are
        // chrome in fixed-size hit targets, not text companions — growing
        // them is what breaks the same 320pt iPad sidebar row the wordmark's
        // comment already warns about (SlackwaterApp.swift). Leave fixed;
        // don't "finish the job" here.
        GlassEffectContainer {
            HStack(alignment: .top) {
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
                // Title pill (prototype: Fraunces 19 name over mono region).
                VStack(spacing: 2) {
                    Text(name)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                    MonoLabel(text: region, color: SN.foam.opacity(0.8), tracking: 1.5)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                // Scoped to the pill itself, not the whole header — the back
                // button and favorite star sit either side of this in the same
                // HStack, and a wider hit target would swallow their taps
                // (issue #32 design note).
                .contentShape(Rectangle())
                .onTapGesture {
                    // Lookup should never fail post-itemId-fix (every detail's
                    // favoriteId is a catalog-exact StationItem id); a miss is
                    // a no-op, not a crash.
                    if let item = StationItem.byId[favoriteId] { openMapFocused(item) }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("map-header-title")
                Spacer()
                // Favorite star — the back button's mirror (design pass
                // item 4a): same 44pt circle chrome, top-right. It is the
                // ONLY thing in this slot: return-to-now used to share the
                // row and shoved the star sideways every time you scrubbed
                // (M52), so it moved to the scrub card's readout row (ReturnToNowSlot in Theme.swift).
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
        .padding(.horizontal, 16)
        .padding(.top, 62)   // clears the status bar; header ignores the top safe area
        .padding(.bottom, mapHeaderBottomMargin)
        .frame(maxWidth: .infinity)
        .background {
            StationMapView(latitude: latitude, longitude: longitude)
            // Scrim: dark at the top for the title pill, lighter into the
            // scrub card below (prototype "scrim" gradient stops, collapsed
            // to two — the middle stops were tuned for the old 420pt hero
            // and read as a flat wash at a third).
            LinearGradient(stops: [
                .init(color: Color(hex: 0x05122A, opacity: 0.80), location: 0),
                .init(color: Color(hex: 0x05122A, opacity: 0.35), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            .allowsHitTesting(false)
        }
        .clipped()
        .background(Color(hex: 0x05122A))
        // Every detail type is built on this header, so arming the edge-swipe
        // here arms it for all four (tide, current, derived gate, CHS waiting).
        .background(InteractivePopEnabler())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail-map-header")
    }
}

/// Restores the edge-swipe-back that the custom chrome costs us.
///
/// Root cause (M52): the app hides the nav bar everywhere —
/// `.toolbar(.hidden, for: .navigationBar)` on the stack and on every detail —
/// because the map hero carries its own back button. UIKit's
/// `setNavigationBarHidden:` disables `interactivePopGestureRecognizer` as a
/// side effect, so on iPhone the only way out of a detail was the button.
/// Re-enabling the recognizer needs a delegate (its own is nil'd with the bar),
/// and the delegate must refuse to begin on the root — otherwise a swipe on the
/// list wedges the navigation controller.
///
/// It stays an edge gesture, so it never competes with the timeline strip's
/// horizontal scrub: the strip's UIScrollView owns every pan that doesn't start
/// within the screen-edge margin.
struct InteractivePopEnabler: UIViewControllerRepresentable {
    final class PopDelegate: NSObject, UIGestureRecognizerDelegate {
        weak var nav: UINavigationController?
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            (nav?.viewControllers.count ?? 0) > 1
        }
    }

    final class Host: UIViewController {
        private let popDelegate = PopDelegate()
        override func viewDidLoad() {
            super.viewDidLoad()
            view.isUserInteractionEnabled = false  // pure plumbing, never a hit target
        }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard let nav = navigationController,
                  let pop = nav.interactivePopGestureRecognizer else { return }
            popDelegate.nav = nav
            pop.delegate = popDelegate
            pop.isEnabled = true
        }
    }

    func makeUIViewController(context: Context) -> Host { Host() }
    func updateUIViewController(_ vc: Host, context: Context) {}
}

/// The header's map: centered on the station, station zoom, non-interactive.
/// Same style pipeline as the discovery map (land PMTiles floor, Seascape
/// composed in when reachable).
private struct StationMapView: UIViewRepresentable {
    let latitude: Double
    let longitude: Double

    final class Coordinator { var styler: MapStyler? }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero)
        map.allowsScrolling = false
        map.allowsZooming = false
        map.allowsRotating = false
        map.allowsTilting = false
        map.attributionButtonPosition = .bottomLeft
        map.logoViewPosition = .bottomLeft
        context.coordinator.styler = MapStyler(
            map: map, cacheName: "header",
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            zoom: stationZoom)
        return map
    }

    func updateUIView(_ uiView: MLNMapView, context: Context) {}
}
