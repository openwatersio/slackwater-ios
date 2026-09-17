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

    /// The fact, the ask, and then the reason — in that order on purpose. A
    /// page that opens with the licence argument is a page defending itself;
    /// one that opens with "not yet" is answering the question that was asked.
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

            // The detail, after the ask — "some of the text you have as the
            // extra". No publisher name and no licence id in the body: those
            // are true, and they are also the two things a boater standing in
            // Gijon has no use for. They sit in `provenance` below instead.
            Text("Why: this station's predictions are published under a licence "
                 + "that allows non-commercial use only, so an app that charges "
                 + "for anything has no right to serve them. It isn't a bug and "
                 + "it isn't a gap in the data — what's missing is permission, "
                 + "and getting it means paying for a commercial licence.")
                .font(.footnote)
                .lineSpacing(3)
                .foregroundStyle(SN.foam.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
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

    /// The ask.
    ///
    /// "Chasing down", not "buys", and "getting it means paying" rather than
    /// "the rights are for sale". Upstream's own note says the GESLA provider
    /// RESTRICTS commercial use; nothing on record says it sells commercial
    /// terms at any price. Issue #401 frames the blocker as the cost of the
    /// rights, which is the working assumption — but the shipped sentence
    /// promises an effort, not an outcome, because that is the part we can
    /// stand behind. Firm this up once a provider has actually quoted.
    ///
    /// ponytail: PROSE ONLY while there is no SKU — `PremiumStore`
    /// has nothing on sale (PremiumView still renders "Premium isn't on sale
    /// yet"), and a button that opens a sheet which cannot sell anything is a
    /// second dead end one screen after the first. When #155's yearly plan is
    /// live this is where its buy button goes, under this same heading; the
    /// paragraph below it already says what the money is for.
    private var supportAsk: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("We need your help")
                .font(.callout.weight(.semibold))
                .foregroundStyle(SN.leaf)
            Text("Commercial licences cost money, and Slackwater is paid for by "
                 + "the people who use it. A plan that funds them is coming — "
                 + "chasing down stations like this one is what it pays for.")
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
    private var provenance: some View {
        Text("Named from \(station.source) (SEANOE), whose record for this station "
             + "is licensed \(station.license) — non-commercial use only.")
            .font(.caption2)
            .foregroundStyle(SN.foam.opacity(0.45))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .accessibilityIdentifier("unavailable-provenance")
    }
}
