// Slackwater — GPL v3. The page behind an unavailable station's ring (issue
// #401): why there are no predictions here, how that changes, and the nearest
// stations that do have them.
import SwiftUI

/// A station we know about and may never serve, given a page of its own.
///
/// The map card is deliberately almost wordless — "not yet available" and one
/// link — because someone tapping a ring in a harbour wants to know whether
/// the app is broken, not to read about licensing. This is where the rest goes
/// for the people who want it, in the order the ask deserves: the plain fact,
/// then what would change it, then the detail, then somewhere else to go.
///
/// It is NOT a `ScrubDetailScaffold`. That scaffold is a strip, a scrub card
/// and a schedule over a timeline, and the whole point of this station is that
/// there is no timeline — so this composes the two pieces that still apply,
/// `DetailHeader` and `NearbySection`, and nothing else.
struct UnavailableDetailView: View {
    let station: UnavailableStation

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 14) {
                    // `favoritable: false` — see DetailHeader. Share resolves
                    // to nil on its own (no slug is ever minted for a station
                    // that has no page on the web), so no flag is needed there.
                    DetailHeader(name: station.name, region: station.region,
                                 favoriteId: station.id,
                                 topSafeInset: geo.safeAreaInsets.top,
                                 favoritable: false)
                    explanation
                    NearbySection(unavailable: station)
                    provenance
                }
                .padding(.bottom, 32)
            }
            .ignoresSafeArea(edges: .top)
        }
        .background(CanvasBackground())
        // Every detail hides the bar, not just the stack — `DetailHeader`
        // carries its own back button, and without this the system's renders
        // above it and the page shows TWO. See InteractivePopEnabler, which
        // also explains why hiding the bar is what costs the edge-swipe (and
        // gives it back; the header brings the enabler with it).
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("unavailable-detail")
    }

    /// The fact, then the ask. In that order on purpose: a page that opens
    /// with an explanation is a page defending itself; one that opens with
    /// "not yet" is answering the question that was actually asked.
    ///
    /// NO REASON GIVEN, deliberately. An earlier draft explained the
    /// non-commercial licence and said buying it was the whole cost. We do not
    /// know that. The licence is real, but what it would take to serve this
    /// station is not: it might be a licence with a price, it might be a
    /// contact at the authority that runs the gauge, and #428 found that most
    /// of these records reach us through a chain whose upstream may permit
    /// commercial use already — in which case nothing needs buying at all.
    /// Stating a cause we have not established is how a page meant to stop
    /// people assuming a bug starts making a different wrong claim.
    private var explanation: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Not yet available", systemImage: "lock")
                .font(.title3.weight(.semibold))
                .foregroundStyle(SN.paper)

            Text("There is a real tide station here, and Slackwater can't publish "
                 + "predictions for it yet.")
                .font(.callout)
                .foregroundStyle(SN.foam.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            supportAsk
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SN.steel.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(SN.steel.opacity(0.35), lineWidth: 0.5))
        .padding(.horizontal, 16)
        // `children: .contain` is what puts this block in the accessibility
        // tree at all — an identifier on a bare VStack names nothing, and
        // SwiftUI exposes only the Texts inside it. `.contain` rather than
        // `.combine` so the paragraphs stay separately navigable.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("unavailable-explanation")
    }

    /// The ask, which is for information rather than for money. Whoever is
    /// standing at this harbour may well know who runs the gauge, and that is
    /// worth more to us right now than a subscription — we do not yet know
    /// which stations money can even fix (#428).
    ///
    /// ponytail: PROSE ONLY, no button yet. The inline "Contact us" this wants
    /// belongs on the shared support helpers in #422 (`supportEmail`,
    /// `reportMailURL`, and the clipboard fallback for a device with no mail
    /// account) — re-implementing a mailto here would duplicate the
    /// `&=?+` encoding gotcha that file already documents. Wire it when #422
    /// lands; note `reportBody` resolves its station name through
    /// `StationItem.byId`, which misses an unavailable id, so it needs a
    /// fallback to `UnavailableStation.byId` at the same time.
    private var supportAsk: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("We need your help")
                .font(.callout.weight(.semibold))
                .foregroundStyle(SN.leaf)
            Text("We don't yet know what it would take to add this one. If you "
                 + "know a contact for this station, or anything about how its "
                 + "data is licensed, please get in touch.")
                .font(.footnote)
                .lineSpacing(3)
                .foregroundStyle(SN.foam.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("unavailable-support-ask")
    }

    /// Who this station's identity came from and under what terms — the
    /// honest provenance, kept to the footnote it deserves. Settings' "Data &
    /// attribution" section is where source credits live; this is the one row
    /// that names them per station, because "which licence, exactly" is a fair
    /// question with a real answer.
    ///
    /// "Named from", not "published by". The same SEANOE deposit is credited
    /// in Settings under CC BY 4.0, because its other half is CC BY 4.0 — so a
    /// line reading "published by TICON-4 under cc-by-nc-4.0" scans as the app
    /// contradicting itself. What is true is narrower: we took the NAME from
    /// that source, and that source's record for THIS station is the
    /// non-commercial one.
    ///
    /// It states the licence and stops. No "non-commercial use only" gloss:
    /// that reads as the reason this station is missing, and the body above
    /// deliberately does not claim to know the reason. This is where the name
    /// came from, nothing more.
    private var provenance: some View {
        Text("Named from \(station.source) (SEANOE), whose record for this "
             + "station is licensed \(station.license).")
            .font(.caption2)
            .foregroundStyle(SN.foam.opacity(0.45))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .accessibilityIdentifier("unavailable-provenance")
    }
}
