// Slackwater — GPL v3. The first-run location gate, and the two handoffs it
// hands the station list.
import SwiftUI

// MARK: - First-run gate

struct GateView: View {
    @AppStorage(seenGateKey) private var seenGate = false
    @AppStorage(unitsKey, store: AppGroup.defaults) private var units = "imperial"
    @ObservedObject private var loc = LocationService.shared
    @State private var asked = false
    private let exampleStation = StationIndex.bundled.tides.first { $0.id == "noaa/9449880" }

    var body: some View {
        ZStack {
            CanvasBackground()
            // Scroll at accessibility sizes; keep the ordinary layout centred.
            GeometryReader { geo in
              ScrollView {
                VStack(spacing: 0) {
                HStack(alignment: .bottom) {
                    Text("Slackwater")
                        .font(.largeTitle.weight(.semibold))
                        .foregroundStyle(SN.paper)
                    Spacer()
                }
                .padding(.horizontal, 22)
                .padding(.top, 6)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tide and Current predictions nearby.")
                    Text("Keeps working offline.")
                }
                .font(.subheadline)
                .foregroundStyle(SN.foam)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22)
                .padding(.top, 12)

                Spacer()

                if loc.locating {
                    ProgressView()
                        .controlSize(.large)
                        .tint(SN.leaf)
                    Text("Finding nearby tides and currents…")
                        .font(.callout)
                        .foregroundStyle(SN.foam.opacity(0.7))
                        .padding(.top, 22)
                } else {
                    if let exampleStation {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Real example station")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(SN.foam)
                            StationCardView(info: exampleStation, imperial: units == "imperial")
                                .dynamicTypeSize(DynamicTypeSize.xSmall ... .xxxLarge)
                        }
                        .frame(maxWidth: 360)
                        .padding(.horizontal, 22)
                    }
                    Text("Your location stays on this device.")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(SN.foam)
                        .frame(maxWidth: 320)
                        .padding(.top, 24)
                        .padding(.horizontal, 22)
                    Button {
                        asked = true
                        loc.request()
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: "location.fill")
                            Text("Find tides near me")
                        }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(SN.navyDeep)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                        .padding(.vertical, 12)
                        .frame(minHeight: 54)
                        .background(SN.leaf, in: Capsule())
                    }
                    .padding(.top, 16)
                    .padding(.horizontal, 22)
                    Button {
                        gateSearchHandoff = true
                        seenGate = true
                    } label: {
                        Text("Search for a place")
                            .font(.subheadline)
                            .underline()
                            .foregroundStyle(SN.foam.opacity(0.8))
                            .padding(.vertical, 12)
                            .frame(minHeight: 44)
                    }
                    .padding(.top, 8)
                    .padding(.horizontal, 22)
                }

                Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
              }
            }
        }
        // The gate resolves when the ask resolves — a fix, or a denial. Either
        // way the choice is made and the list takes over (denied shows the
        // amber card there).
        .onChange(of: loc.locating) { _, locating in
            if asked && !locating { seenGate = true }
        }
    }
}

// MARK: - Handoffs to the station list

/// Set by the gate's "or search" bypass, consumed by the list's first appear —
/// the bypass lands straight in the search experience.
var gateSearchHandoff = false

/// Set by a widget deep link that arrives before the gate is answered (RootView),
/// consumed by the list's first appear — same handoff, one screen later.
var pendingDeepLink: URL?

/// The moment a shared station link carried, set by `StationListView.open`
/// and consumed by the first `ScrubDetailScaffold` to appear (#187). The link
/// opens its station by pushing it, and the pushed detail is what owns the
/// scrub time — so the instant waits here for it. Every `open` resets it, so
/// a link's moment can never reach a station opened later by hand.
var pendingScrubInstant: Date?
