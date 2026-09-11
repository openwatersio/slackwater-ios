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
    /// The context curve (`StationCardGraph.window` wide) behind the content.
    var graph: StationCardGraph? = nil
    /// The list's rounded clip and shadow. The widget passes false: its own
    /// container clips, and a shadow inside a widget is a smear. Without
    /// chrome the card also fills its container, so the widget's family
    /// sets the height and the curve gets the room under the header.
    var chrome = true
    /// The list's card heights by default; the widget lets the card fill
    /// its family instead.
    var minHeight: CGFloat? = nil
    /// The location-arrow glyph before the region, in place of the words
    /// "Current Location" — the widget has no room to spell it out
    /// (MyLocationTile carries the same mark in the list).
    var locationMark = false
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
                    if locationMark {
                        Image(systemName: "location.north.fill")
                            .font(.caption2)
                            .rotationEffect(.degrees(45))
                            .foregroundStyle(SN.foam)
                    }
                    // The widget has no room for a wrapped region line: caption2, one line.
                    Text(region)
                        .font(chrome ? .caption : .caption2)
                        .foregroundStyle(SN.foam)
                        .lineLimit(chrome ? nil : 1)
                        .fixedSize(horizontal: false, vertical: chrome)
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
        let placeholder = status?.showsPlaceholder == true
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
        // A curve or its loading placeholder is taller: an identity band up
        // top, then room for the curve and its extreme labels.
        .frame(maxWidth: .infinity, minHeight: minHeight ?? (graph == nil && !placeholder ? 96 : 168),
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
                if let graph {
                    graph.padding(.top, 54).padding(.horizontal, -3)
                } else if placeholder, let status {
                    StationCardPlaceholder(animated: status == .downloading)
                        .padding(.top, 54).padding(.horizontal, -3)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: chrome ? 24 : 0, style: .continuous))
        .shadow(color: chrome ? SN.shadow.opacity(0.24) : .clear, radius: chrome ? 12 : 0, y: chrome ? 10 : 0)
    }
}

/// A data-free echo of the card curve and its time axis. Only an active
/// download moves; queued and on-demand rows stay flat.
private struct StationCardPlaceholder: View {
    let animated: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if animated && !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let phase = timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 1.4) / 1.4
                marks.foregroundStyle(LinearGradient(
                    colors: [SN.foam.opacity(0.12), SN.foam.opacity(0.34), SN.foam.opacity(0.12)],
                    startPoint: UnitPoint(x: phase - 0.45, y: 0.5),
                    endPoint: UnitPoint(x: phase + 0.45, y: 0.5)))
            }
        } else {
            marks.foregroundStyle(SN.foam.opacity(0.2))
        }
    }

    private var marks: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            Path { path in
                path.move(to: CGPoint(x: -4, y: h * 0.46))
                for x in stride(from: CGFloat.zero, through: w + 4, by: 4) {
                    let y = h * (0.46 - 0.26 * sin(x / max(w, 1) * 4 * .pi))
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round))

            ForEach([0.22, 0.5, 0.78], id: \.self) { x in
                Capsule()
                    .frame(width: 34, height: 6)
                    .position(x: w * x, y: h - 10)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The card's trailing reading block, one case per station kind.
///
/// `.tide`: current height plus the rising/falling indicator.
///
/// `.current`: signed velocity — speed + set arrow + word, Slack in the go
/// colour inside a window. `tilde` marks a provisional (60-day) reading.
///
/// `.gate`: a derived gate's phase and flow arrow; no speed exists to show.
struct ConditionsItem: View {
    enum Reading {
        case tide(CardState, imperial: Bool)
        case current(signed: Double, deg: Double, unit: String, tilde: Bool = false, inWindow: Bool = false)
        case gate(DerivedPhase)
    }
    let reading: Reading
    /// One row instead of two — the small widget's hero (current-charts
    /// §15.5). The tide keeps its arrow and drops the word; the current keeps
    /// Slack, then the arrow before its cardinal. The phase word is spoken,
    /// not shown: the arrow's colour is the phase.
    var compact = false

    var body: some View {
        switch reading {
        case .tide(let state, let imperial):
            // The detail lead's glyph and inks (testTurnInksAgreeAcrossChartPillAndLead):
            // rising wears the chart's high teal, not the flood blue — direction
            // colour belongs to currents.
            let tint = state.rising ? SN.graphHigh : SN.graphLow
            let arrow = Text(Image(systemName: state.rising ? "arrow.up.right" : "arrow.down.right"))
                .font(.caption).foregroundStyle(tint)
            let spoken = "\(formatHeight(state.height, imperial: imperial)) \(heightUnit(imperial: imperial)), \(state.rising ? "rising" : "falling")"
            let value = Text(formatHeight(state.height, imperial: imperial))
                .font(.title3.monospacedDigit()).fontWeight(.bold)
             + Text(" \(heightUnit(imperial: imperial))")
                .font(.body)
            if compact {
                (value + Text(" ") + arrow)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .accessibilityLabel(spoken)
            } else {
                value.foregroundStyle(.white)
                HStack(spacing: 4) {
                    Text(state.rising ? "Rising" : "Falling").font(.caption)
                        .foregroundStyle(SN.foam.opacity(0.6))
                    arrow
                }
            }

        case .current(let signed, let deg, let unit, let tilde, let inWindow):
            // Always the speed and the set (current-charts §15.2): a pill
            // states a phase without either.
            let phase = currentPhase(signed: signed)
            // Inside a slack window — the same run the curve draws green, from
            // the shared predicate (current-charts §6.1, §15.2) — the word is
            // Slack in the go colour whatever the instantaneous phase word says.
            let slack = inWindow || phase == .slack
            let spoken = "\(formatSpeed(abs(signed), unit: unit)) \(speedUnitLabel(unit)), \(slack ? "slack" : "\(phase.word), setting \(compass16(deg))")"
            let value = (Text((tilde ? "~" : "") + formatSpeed(abs(signed), unit: unit))
                .font(.title3.monospacedDigit()).fontWeight(.bold)
             + Text(" \(speedUnitLabel(unit))")
                .font(.body))
                .foregroundStyle(.white)
            // Direction-first (#59): a novice reads the arrow + cardinal;
            // the word demotes to a dimmer label. "Slack" wears the go
            // colour — the same meaning it has everywhere else. Under
            // 0.05 kn the set gives way to a neutral mark of the same
            // footprint so the header never resizes.
            let tint = slack ? SN.go : phase == .flood ? SN.flood : SN.ebb
            if compact {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    // The number never truncates; a tight row loses the cardinal.
                    value.layoutPriority(1)
                    if slack { Text("Slack").font(.caption).foregroundStyle(tint) }
                    set(deg: deg, signed: signed, tint: tint, font: .caption, arrowFirst: true)
                }
                .lineLimit(1)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(spoken)
            } else {
                value
                HStack(spacing: 4) {
                    // The word stays neutral like the detail lead's; only the
                    // arrow speaks the phase colour. Slack keeps SN.go —
                    // testSlackIsGreenWhereverItAppears.
                    Text(slack ? "Slack" : phase.word).font(.caption2)
                        .foregroundStyle(slack ? tint : SN.foam.opacity(0.6))
                    set(deg: deg, signed: signed, tint: tint, font: .caption2, arrowFirst: false)
                }
            }
        case .gate(let phase):
            let tint = phase == .flood ? SN.flood : phase == .ebb ? SN.ebb : SN.go
            HStack(spacing: 4) {
                Text(phase.word).font(.caption2)
                Image(systemName: phase == .flood ? "arrow.forward" : phase == .ebb
                      ? "arrow.backward" : "arrow.right.and.line.vertical.and.arrow.left")
            }
            .foregroundStyle(tint)
        }
    }

    /// The set: cardinal and bearing arrow by the sign of the velocity, or a
    /// neutral mark of the same footprint under 0.05 kn.
    @ViewBuilder
    private func set(deg: Double, signed: Double, tint: Color, font: Font, arrowFirst: Bool) -> some View {
        if abs(signed) < 0.05 {
            Text("•").font(font).foregroundStyle(SN.foam.opacity(0.4))
                .frame(width: 30)
        } else {
            HStack(spacing: arrowFirst ? 2 : 4) {
                if arrowFirst { CompassArrow(deg: deg) }
                Text(compass16(deg))
                if !arrowFirst { CompassArrow(deg: deg) }
            }.font(font).foregroundStyle(tint)
        }
    }
}
