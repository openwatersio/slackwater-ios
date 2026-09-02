// Slackwater — GPL v3. The station card shell and its trailing reading
// block, shared by the list and the home-screen widget.
import SwiftUI
import TideEngine

/// The one card shell. Every variant renders through it, so the chrome and
/// the ViewThatFits shed step have a single place to live and cannot drift.
///
/// `trailing` is the reading block (a big value, a phase pill, or nothing at
/// all for a pending card). `status` is the strip below it.
///
/// Two layouts, one shed step: the distance drops when the width can't hold
/// it (the list's grouping already answers "near me"). The name, region and
/// reading are load-bearing at every size and render unconditionally — the
/// region is the one field disambiguating same-named stations, so it must
/// never shed.
///
/// No kind mark. A wave or dome glyph is not a universal symbol: it teaches a
/// new reader nothing, and a returning reader scans the names. Nothing
/// announces kind, VoiceOver included — an `accessibilityLabel` naming a kind
/// the card shows no one would tell a VoiceOver user something the card tells
/// nobody else. Parity, not preservation.
struct StationCard<Trailing: View>: View {
    let name: String
    let region: String
    var km: Double? = nil
    /// What this card is waiting on — an icon and two words below the whole
    /// row, at full card width (#93). Kept as its own slot rather than a flag
    /// on `detail`: the two differ in opacity, width, and font treatment, and
    /// conflating them regresses both.
    var status: CardStatus? = nil
    var opacity: Double = 1
    /// The context curve (`StationCardGraph.window` wide) behind the content; nil
    /// for pending cards and derived gates (no magnitude to draw).
    var graph: StationCardGraph? = nil
    /// The list's rounded clip and shadow. The widget passes false: its own
    /// container clips, and a shadow inside a widget is a smear. Without
    /// chrome the card also fills its container, so the widget's family
    /// sets the height and the curve gets the room under the header.
    var chrome = true
    /// The list's card heights by default; the widget lets the card fill
    /// its family instead.
    var minHeight: CGFloat? = nil
    @ViewBuilder var trailing: () -> Trailing

    /// The identity row — the only thing `extras` changes, and so the only
    /// thing `ViewThatFits` measures. `message` and the card chrome sit
    /// outside it in `body`; see the note there for why that matters.
    @ViewBuilder
    func content(extras: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .allowsTightening(true)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(region)
                        .font(.caption)
                        .foregroundStyle(SN.foam)
                        .fixedSize(horizontal: false, vertical: true)
                    if extras, let km {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(SN.foam.opacity(0.5))
                        Text(formatNm(km))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(SN.foam)
                    }
                }
            }
            Spacer(minLength: 8)
            // Same rhythm as the identity column's name/region stack.
            VStack(alignment: .trailing, spacing: 2) { trailing() }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Which candidate wins is verified by screenshot, not by
            // unit test — ViewThatFits exposes no way to ask.
            ViewThatFits(in: .horizontal) {
                content(extras: true)
                content(extras: false)
            }
            // The dimming a pending card asks for is about its IDENTITY being
            // quieter than a station with numbers — not about its status. Left
            // on the whole card it also dims the strip, and amber at 0.82 over
            // the card measures ~4.1:1, under AA for caption text where the
            // full-strength 4.71:1 clears it (docs/testflight.md).
            .opacity(opacity)
            // The status strip sits OUTSIDE the ViewThatFits, and that
            // placement is load-bearing: `ViewThatFits` compares each
            // candidate's IDEAL width, and a `Text`'s ideal width is its
            // unwrapped single line — measured inside the candidates, a long
            // status line's ~470pt ideal dominates both, no candidate ever
            // "fits", and every card carrying one falls through to the
            // reduced layout regardless of width. The strip is identical in
            // both candidates, so it has no business being measured by the
            // picker — shorter copy does not change that, it only shrinks the
            // window in which the bug would be visible.
            if let status {
                CardStatusStrip(status: status)
                    .padding(.top, 10)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        // A curve card is taller: an identity band up top (the curve's top
        // inset below), then room for the curve and its extreme labels.
        .frame(maxWidth: .infinity, minHeight: minHeight ?? (graph == nil ? 96 : 168),
               maxHeight: chrome ? nil : .infinity, alignment: .topLeading)
        .background {
            ZStack {
                SN.cardFill
                // Top inset clears the two identity rows and the current
                // reading, so the curve owns the card's lower band. The
                // negative horizontal padding renders the canvas 3pt wider
                // than the card each side; the clipShape trims it, so the
                // curve exits through the edge on its own slope no matter
                // where any builder's last sample lands.
                if let graph { graph.padding(.top, 54).padding(.horizontal, -3) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: chrome ? 24 : 0, style: .continuous))
        .shadow(color: chrome ? SN.shadow.opacity(0.24) : .clear, radius: chrome ? 12 : 0, y: chrome ? 10 : 0)
    }
}

/// The card's trailing reading block, one case per station kind.
///
/// `.tide`: current height plus the rising/falling indicator.
///
/// `.current`: signed velocity — speed + set arrow + word, Slack in the go
/// colour inside a window; `countdownTo` swaps the speed for a timer on
/// counting surfaces. `tilde` marks a provisional (60-day) reading.
///
/// `.gate`: a derived gate's phase pill — the web's words, flood / ebb /
/// slack; no speed exists to show (`DerivedGateCardState`). Slack takes
/// SN.go, not the neutral chip flood/ebb still use — otherwise the glyph
/// beside it reads green while this pill reads grey, the exact collision
/// the detail views guard against (testSlackIsGreenWhereverItAppears).
struct ConditionsItem: View {
    enum Reading {
        case tide(CardState, imperial: Bool)
        case current(signed: Double, deg: Double, unit: String, tilde: Bool = false, countdownTo: Date? = nil)
        case gate(DerivedPhase)
    }
    let reading: Reading

    var body: some View {
        switch reading {
        case .tide(let state, let imperial):
            let tint = state.rising ? SN.rising : SN.falling

            (Text(formatHeight(state.height, imperial: imperial))
                .font(.title3.monospacedDigit()).fontWeight(.bold)
             + Text(" \(heightUnit(imperial: imperial))")
                .font(.body))
                .foregroundStyle(.white)
            HStack(spacing: 4) {
                Text(state.rising ? "Rising" : "Falling").font(.caption).foregroundStyle(tint.opacity(0.6))
                Text(state.rising ? "▲" : "▼").font(.caption)
            }.foregroundStyle(tint)

        case .current(let signed, let deg, let unit, let tilde, let countdownTo):
            // Always the speed and the set (current-charts §15.2): a pill
            // states a phase without either. Inside a window a counting
            // surface (the widget) shows the time to the closing instead of
            // the speed (§15.3); the list passes no countdown.
            let phase = currentPhase(signed: signed)
            // A countdown that has already elapsed by render time (a widget entry outliving its window) falls back to the speed; Date.now...end must never be built with end in the past.
            if let end = countdownTo, end > Date.now {
                if end.timeIntervalSinceNow > 7_200 {
                    Text("> 2 hrs")
                        .font(.title3.monospacedDigit()).fontWeight(.bold)
                        .foregroundStyle(.white)
                } else {
                    Text(timerInterval: Date.now...end, countsDown: true)
                        .font(.title3.monospacedDigit()).fontWeight(.bold)
                        .foregroundStyle(.white)
                }
            } else {
                (Text((tilde ? "~" : "") + formatSpeed(abs(signed), unit: unit))
                    .font(.title3.monospacedDigit()).fontWeight(.bold)
                 + Text(" \(speedUnitLabel(unit))")
                    .font(.body))
                    .foregroundStyle(.white)
            }
            // Direction-first (#59): a novice reads the arrow + cardinal;
            // the word demotes to a dimmer label. "Slack" wears the go
            // colour — the same meaning it has everywhere else. Under
            // 0.05 kn the set gives way to a neutral mark of the same
            // footprint so the header never resizes.
            let tint = phase == .slack ? SN.go : phase == .flood ? SN.flood : SN.ebb
            HStack(spacing: 4) {
                Text(phase.word).font(.caption2)
                    .foregroundStyle(tint.opacity(phase == .slack ? 1 : 0.6))
                if abs(signed) < 0.05 {
                    Text("•").font(.caption2).foregroundStyle(SN.foam.opacity(0.4))
                        .frame(width: 30)
                } else {
                    Text(compass16(deg)).font(.caption2).foregroundStyle(tint)
                    CompassArrow(deg: deg).font(.caption2).foregroundStyle(tint)
                }
            }.foregroundStyle(tint)
        case .gate(let phase):
            Text(phase == .flood ? "FLOOD" : phase == .ebb ? "EBB" : "SLACK")
                .font(.caption2.monospaced().weight(.medium)).tracking(1)
                .foregroundStyle(phase == .slack ? SN.navyDeep : .white)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(phase == .slack ? SN.go : Color.white.opacity(0.18), in: Capsule())
        }
    }
}
