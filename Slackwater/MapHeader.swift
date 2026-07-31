// Slackwater — GPL v3. The detail-view map header (map-hero spec §1/§2, header
// portion only — no particle field, no universal scrub yet): the station's map
// is the hero surface, scrim-darkened so the overlaid title reads (spec §5a/§7
// legibility risk), with the prototype's back / title-pill / return-to-now
// chrome (TidesApp.dc.html detail hero).
import SwiftUI
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
    /// Shown while scrubbed away from now (prototype st.showNow).
    let showReturn: Bool
    let onReturn: () -> Void
    @Environment(\.dismiss) private var dismiss

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
                            .font(.fraunces(19, .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        MonoLabel(text: region, size: 9, color: SN.foam.opacity(0.8), tracking: 1.5)
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
                    } else {
                        Color.clear.frame(width: 44, height: 44)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 62)  // clears the status bar; header ignores the top safe area
                Spacer()
            }
        }
        .frame(height: mapHeaderHeight)
        .clipped()
        .background(Color(hex: 0x05122A))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail-map-header")
    }
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
