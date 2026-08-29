// Slackwater — GPL v3. The first-run location gate, and the two handoffs it
// hands the station list.
import SwiftUI

// MARK: - First-run gate

struct GateView: View {
    @AppStorage(seenGateKey) private var seenGate = false
    @ObservedObject private var loc = LocationService.shared
    @State private var asked = false

    var body: some View {
        ZStack {
            CanvasBackground()
            // The gate is one screenful of fixed copy, and since the type
            // scales that screenful stops fitting at the top accessibility
            // sizes. Measured at AX5 on both devices:
            // "See tides near you" came out "See tides nea…" and the subtitle
            // "Turn on location and…", because SwiftUI resolves a too-short
            // VStack by TRUNCATING its Texts, silently. A ScrollView gives the
            // copy the height it needs; `minHeight: geo.size.height` keeps the
            // Spacers' centred layout for every size that still fits, so
            // nothing moves below AX5.
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

                Spacer()

                if loc.locating {
                    ProgressView()
                        .controlSize(.large)
                        .tint(SN.leaf)
                    Text("Finding stations near you…")
                        .font(.callout)
                        .foregroundStyle(SN.foam.opacity(0.7))
                        .padding(.top, 22)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(LinearGradient(
                                colors: SN.gateTile,
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 96, height: 96)
                            .shadow(color: SN.shadow.opacity(0.4), radius: 20, y: 16)
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(SN.foam)
                    }
                    Text("See tides near you")
                        .font(.title.weight(.semibold))
                        .foregroundStyle(SN.paper)
                        .padding(.top, 26)
                    Text("Turn on location to find the \nnearest tide & current stations.")
                        .font(.subheadline)
                        .lineSpacing(3)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(SN.foam.opacity(0.65))
                        .frame(maxWidth: 300)
                        .padding(.top, 10)
                    Button {
                        asked = true
                        loc.request()
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: "location.fill")
                            Text("Use My Location")
                        }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(SN.navyDeep)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                        // Content sizes the capsule; `minHeight` keeps the 54pt
                        // look at default sizes without capping growth. A fixed
                        // `.frame(height: 54)` here silently truncated the label
                        // at accessibility sizes ("Use My…"), because a `Text`
                        // given too little height degrades by DROPPING CONTENT,
                        // not by overflowing — the opposite of an `Image`, which
                        // ignores the proposal and draws past its frame. Text
                        // fails silently; images fail visibly. Never pin a
                        // height around text you need read.
                        .padding(.vertical, 12)
                        .frame(minHeight: 54)
                        .background(SN.leaf, in: Capsule())
                        .shadow(color: SN.leaf.opacity(0.3), radius: 13, y: 10)
                    }
                    .padding(.top, 30)
                    .padding(.horizontal, 22)
                    Button {
                        gateSearchHandoff = true
                        seenGate = true
                    } label: {
                        Text("Or search for a harbor, bay, or channel.")
                            .font(.caption)
                            .foregroundStyle(SN.foam.opacity(0.4))
                    }
                    .padding(.top, 16)
                }

                Spacer()
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
