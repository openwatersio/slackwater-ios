// Slackwater — GPL v3. The detail-view map header (map-hero spec §1/§2, header
// portion only — no particle field, no universal scrub yet): the station's map
// is the hero surface, scrim-darkened so the overlaid title reads (spec §5a/§7
// legibility risk), with the prototype's back / title-pill / return-to-now
// chrome (TidesApp.dc.html detail hero).
import SwiftUI
import UIKit
import MapLibre

/// Prototype hero height (420 of a 874pt frame).
let mapHeaderHeight: CGFloat = 420
/// Prototype per-station zoom (DATA() z: 12.2–13.2).
private let stationZoom = 12.5

struct MapHeader: View {
    let name: String
    let region: String
    let latitude: Double
    let longitude: Double
    /// StationItem id this detail shows — the favorite star toggles it.
    let favoriteId: String
    /// Shown while scrubbed away from now (prototype st.showNow).
    let showReturn: Bool
    let onReturn: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var favorites = FavoritesStore.shared

    var body: some View {
        ZStack {
            StationMapView(latitude: latitude, longitude: longitude)
            // Station pin: the camera is centered on the station, so the pin
            // is a centered dot (prototype mapLayerEl "stn").
            Circle()
                .fill(.white)
                .frame(width: 11, height: 11)
                .background(Circle().stroke(Color(hex: 0x05122A, opacity: 0.6), lineWidth: 3).padding(-3))
                .shadow(color: .white.opacity(0.85), radius: 6)
            // Scrim: dark at the top for the title, dark at the bottom into the
            // scrub card (prototype "scrim" gradient stops).
            LinearGradient(stops: [
                .init(color: Color(hex: 0x05122A, opacity: 0.80), location: 0),
                .init(color: Color(hex: 0x05122A, opacity: 0.20), location: 0.26),
                .init(color: Color(hex: 0x05122A, opacity: 0.10), location: 0.52),
                .init(color: Color(hex: 0x05122A, opacity: 0.75), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            .allowsHitTesting(false)

            VStack {
                HStack(alignment: .top) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                            .background(Color(hex: 0x05122A, opacity: 0.55), in: Circle())
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
                    .background(.ultraThinMaterial,
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .background(Color(hex: 0x05122A, opacity: 0.34),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
                    Spacer()
                    // Favorite star — the back button's mirror (design pass
                    // item 4a): same 44pt circle chrome, top-right. It is the
                    // ONLY thing in this slot: return-to-now used to share the
                    // row and shoved the star sideways every time you scrubbed
                    // (M52), so it moved to its own fixed slot below.
                    let fav = favorites.contains(favoriteId)
                    Button { favorites.toggle(favoriteId) } label: {
                        Image(systemName: fav ? "star.fill" : "star")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(fav ? SN.sun : .white)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                            .background(Color(hex: 0x05122A, opacity: 0.55), in: Circle())
                    }
                    .accessibilityLabel(fav ? "Remove favorite" : "Add favorite")
                    .accessibilityIdentifier("detail-favorite")
                }
                .padding(.horizontal, 16)
                .padding(.top, 62)  // clears the status bar; header ignores the top safe area
                Spacer()
            }
        }
        .frame(height: mapHeaderHeight)
        // Return-to-now: bottom-right of the hero — below the star, above the
        // scrub card — as an OVERLAY, so it occupies the same points whether it
        // is there or not and nothing reflows when a scrub starts or ends.
        .overlay(alignment: .bottomTrailing) {
            if showReturn {
                Button(action: onReturn) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(SN.leaf)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                        .background(Color(hex: 0x05122A, opacity: 0.55), in: Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5))
                }
                .accessibilityLabel("Return to now")
                .accessibilityIdentifier("detail-return-now")
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
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
