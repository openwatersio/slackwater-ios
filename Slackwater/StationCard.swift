import SwiftUI
import TideEngine

/// The one card shell. Every variant renders through it, so the chrome and
/// the ViewThatFits shed step have a single place to live and cannot drift.
///
/// `trailing` is the reading block (a big value, a phase pill, or nothing at
/// all for a pending card). `status` is the strip below it.
///
/// Two layouts, one shed step: distance and detail drop together when the
/// width can't hold them (the list's grouping already answers "near me", and
/// "when" is the detail view's job one tap away). The name, region and reading
/// are load-bearing at every size and render unconditionally — the region is
/// the one field disambiguating same-named stations, so it must never shed.
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
    /// A next-event reading (`High 3.2 m · 14:20`) — mono-digit, sits inside
    /// the identity column beside the glyph.
    var detail: String? = nil
    /// What this card is waiting on — an icon and two words below the whole
    /// row, at full card width (#93). Kept as its own slot rather than a flag
    /// on `detail`: the two differ in opacity, width, and font treatment, and
    /// conflating them regresses both.
    var status: CardStatus? = nil
    var opacity: Double = 1
    @ViewBuilder var trailing: () -> Trailing

    /// The identity row — the only thing `extras` changes, and so the only
    /// thing `ViewThatFits` measures. `message` and the card chrome sit
    /// outside it in `body`; see the note there for why that matters.
    @ViewBuilder
    func content(extras: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    // Wrap, never truncate: a `Text` given too little room
                    // degrades by DROPPING CONTENT ("Vi/ct/…" in the 320pt
                    // iPad sidebar); `fixedSize(vertical:)` makes it take the
                    // height it actually needs instead.
                    .fixedSize(horizontal: false, vertical: true)
                    // ...but a single word wider than the column still breaks
                    // MID-WORD, and the My Location hero is the narrowest card
                    // the app draws (MyLocationTile insets it 8pt a side inside
                    // the same 16pt gutter every other card gets). In the iPad
                    // sidebar that renders the first station a UK user opens as
                    // "Portsmout / h". Tightening buys back the few points that
                    // costs. NOT `minimumScaleFactor`: TypeScaleTests
                    // `testOnlyTheWordmarkShrinks` allows exactly one in the
                    // app and it is the wordmark.
                    .allowsTightening(true)
                // Unconditional — region never sheds: it is the only thing
                // separating same-named stations.
                Text(region)
                    .font(.footnote)
                    .foregroundStyle(SN.foam.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
                if extras, let km {
                    Text(formatNm(km))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(SN.foam.opacity(0.7))
                }
                if extras, let detail {
                    Text(detail)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(SN.foam.opacity(0.92))
                        .padding(.top, 10)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 5) { trailing() }
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
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background(SN.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: SN.shadow.opacity(0.24), radius: 12, y: 10)
    }
}

/// The compact recent-station row body: name over region, current reading
/// trailing in Fraunces. No kind mark, same reason as the cards' — and a row
/// carrying one beside cards without would read as a distinction that isn't
/// there.
struct RecentRowLabel: View {
    let item: StationItem
    let imperial: Bool
    @AppStorage(speedUnitKey, store: AppGroup.defaults) private var speedUnit = "kn"
    // Cache the engine state, format in body — unit switches re-render live.
    // Still the whole card state and not just the number: `reading` needs the
    // slack test and the phase word, which the bare value doesn't carry.
    @State private var tide: CardState?
    @State private var current: CurrentCardState?
    @State private var gate: DerivedGateCardState?  // derived gate: phase word, never a speed
    var body: some View {
        // The name owns the full row width: sharing the line with the
        // reading leaves it ~150pt in the 320pt iPad sidebar — "Deception
        // Pass State Park" comes out "Deception Pas…", and two different
        // stations truncate to the same string. The reading drops to the
        // secondary line, where the region (the least load-bearing text
        // here) is what gives way instead.
        VStack(alignment: .leading, spacing: 2) {
            Text(item.name)
                .font(.callout.weight(.medium))
                .foregroundStyle(SN.paper)
            HStack(spacing: 8) {
                Text(item.region)
                    .font(.caption)
                    .foregroundStyle(SN.foam.opacity(0.55))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(reading)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(SN.foam.opacity(0.7))
                    .lineLimit(1)
                    .layoutPriority(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .task { if tide == nil && current == nil && gate == nil { load() } }
    }

    private var rawId: String {
        if case .current(let s) = item { return s.id }
        return item.id
    }

    private var reading: String {
        if let gate { return gate.phase.word.lowercased() }
        if let current {
            return currentPhase(signed: current.signed) == .slack
                ? "slack" : "\(formatSpeed(abs(current.signed), unit: speedUnit)) \(speedUnitLabel(speedUnit))"
        }
        guard let tide else { return "" }
        return "\(formatHeight(tide.height, imperial: imperial)) \(heightUnit(imperial: imperial))"
    }

    private func load() {
        switch item {
        case .tide(let s):
            tide = s.cardState(at: appNow())
        case .current(let s):
            current = s.cardState(at: appNow())
        case .chs(let info):
            guard case .fitted(let record) = ChsFitService.shared.state(info.id) else { return }
            tide = record.cardState(at: appNow())
        case .chsGate(let info):
            guard case .fitted(let port) = ChsFitService.shared.state(info.reference) else { return }
            gate = DerivedGateRecord(gate: info, port: port).cardState(at: appNow())
        case .chsCurrent(let info):
            guard case .fitted(let record) = ChsFitService.shared.currentState(info.id) else { return }
            current = record.cardState(at: appNow())
        }
    }
}

/// Layout A: kind glyph left, identity (name/region/distance), state right.
/// Fraunces name, big height numeral.
struct StationCardView: View {
    let record: TideStationRecord
    let imperial: Bool
    var km: Double? = nil
    @State private var state: CardState?

    var body: some View {
        StationCard(name: record.name, region: record.region, km: km,
                    detail: state?.next.map { next in
                        "\(next.kind == .high ? "High" : "Low") \(formatHeight(next.height, imperial: imperial)) \(heightUnit(imperial: imperial)) · \(cardTime(next.time, record.tz))"
                    }) {
            if let state {
                (Text(formatHeight(state.height, imperial: imperial))
                    .font(.largeTitle.monospacedDigit())
                 + Text(" \(heightUnit(imperial: imperial))")
                    .font(.body))
                    .foregroundStyle(.white)
                HStack(spacing: 4) {
                    Text(state.rising ? "▲" : "▼").font(.caption2)
                    Text(state.rising ? "Rising" : "Falling").font(.caption2)
                }
                .foregroundStyle(SN.foam.opacity(0.9))
            }
        }
        .task { if state == nil { state = record.cardState(at: appNow()) } }
    }
}

/// A Canadian (CHS) tide port. Fitted: the ordinary tide card, navigable.
/// Not yet fitted: the same card shell with identity and an honest message
/// — never an empty chart, never a spinner to nothing.
struct ChsCardView: View {
    let info: ChsStationInfo
    let imperial: Bool
    var km: Double? = nil
    @ObservedObject private var service = ChsFitService.shared
    @ObservedObject private var net = Connectivity.shared

    var body: some View {
        // Navigation comes from the enclosing row's hidden link (itemCard).
        switch service.state(info.id) {
        case .fitted(let record):
            StationCardView(record: record, imperial: imperial, km: km)
        case .fitting:
            pending(fitting: true)
        case .pending:
            pending()
        case .failed:
            pending(failed: true)
        }
    }

    private func pending(fitting: Bool = false, failed: Bool = false) -> ChsPendingCard {
        ChsPendingCard(name: info.name, region: info.region, id: info.id, km: km,
                       status: cardStatus(id: info.id, fitting: fitting, failed: failed))
    }
}

/// The not-yet-fitted CHS shell: identity + one status strip, no numbers.
/// Shared by the tide ports and the derived gates —
/// a gate is pending exactly while its reference port is.
struct ChsPendingCard: View {
    let name: String
    let region: String
    let id: String
    var km: Double? = nil
    let status: CardStatus

    var body: some View {
        StationCard(name: name, region: region, km: km,
                    status: status,
                    opacity: 0.82,  // visibly quieter than a station with numbers
                    trailing: { EmptyView() })
            // Named per station. "Some card on screen says 'Canadian tidal
            // predictions'" is a unique locator at 21 Canadian stations and
            // meaningless at 1,097 — every undownloaded station says it, so a test
            // waiting for THIS station's copy to go never sees it go.
            .accessibilityIdentifier("chs-pending-\(id)")
    }
}

/// A derived current gate's card (web StationCard's derived layout): identity,
/// "Slack · time" as the next line, and a compact phase pill — a derived gate
/// has no speed, so the reading is never a number (chs/current.ts). Pending
/// while the reference port is unfitted, in the same register as the ports.
struct ChsGateCardView: View {
    let gate: ChsGateInfo
    var km: Double? = nil
    @ObservedObject private var service = ChsFitService.shared
    @ObservedObject private var net = Connectivity.shared
    @State private var state: DerivedGateCardState?

    /// Phase → tone. `static` so tests can call it without mounting the view.
    static func glyphTone(_ phase: DerivedPhase?) -> StationGlyph.Tone {
        switch phase {
        case .flood: .flood
        case .ebb: .ebb
        case .slack: .slack
        case nil: .unknown
        }
    }

    var body: some View {
        switch service.state(gate.reference) {
        case .fitted(let port):
            fittedCard(DerivedGateRecord(gate: gate, port: port))
        case .fitting:
            pending(fitting: true)
        case .pending:
            pending()
        case .failed:
            pending(failed: true)
        }
    }

    /// A derived gate waits on its reference PORT's tidal download.
    private func pending(fitting: Bool = false, failed: Bool = false) -> ChsPendingCard {
        ChsPendingCard(name: gate.name, region: gate.region, id: gate.id, km: km,
                       status: cardStatus(id: gate.reference, fitting: fitting, failed: failed))
    }

    private func fittedCard(_ record: DerivedGateRecord) -> some View {
        StationCard(name: gate.name, region: gate.region, km: km,
                    detail: state?.nextSlack.map { next in
                        "Slack · \(cardTime(next.time, gate.tz))"
                    }) {
            if let state {
                // The web's phase-pill words: flood / ebb / slack. Slack
                // takes SN.go, not the neutral chip flood/ebb use —
                // otherwise the glyph beside it reads green while this
                // pill reads grey, the exact collision the detail views
                // guard against (testSlackIsGreenWhereverItAppears).
                Text(state.phase == .flood ? "FLOOD" : state.phase == .ebb ? "EBB" : "SLACK")
                    .font(.caption2.monospaced().weight(.medium)).tracking(1)
                    .foregroundStyle(state.phase == .slack ? SN.navyDeep : .white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(state.phase == .slack ? SN.go : Color.white.opacity(0.18), in: Capsule())
            }
        }
        .task { if state == nil { state = record.cardState(at: appNow()) } }
    }
}

/// A validated CHS current gate. Fitted: the ordinary current card — real
/// velocities, navigable. Not yet fitted: the pending shell in the established
/// register, naming currents — never an empty chart.
struct ChsCurrentGateCardView: View {
    let gate: ChsCurrentGateInfo
    var km: Double? = nil
    @ObservedObject private var service = ChsFitService.shared
    @ObservedObject private var net = Connectivity.shared
    /// Only ever read for an online gate — a fitted gate never touches this.
    @State private var onlineStore: ChsOnlineStore?

    var body: some View {
        // Navigation comes from the enclosing row's hidden link (itemCard).
        Group {
            if gate.isOnline {
                onlineCard
            } else {
                switch service.currentState(gate.id) {
                case .fitted(let record):
                    CurrentCardView(record: record, km: km,
                                    provisional: service.isProvisional(gate.id) ? gate : nil)
                case .fitting:
                    pending(fitting: true)
                case .pending:
                    pending()
                case .failed:
                    pending(failed: true)
                }
            }
        }
        .task { refreshOnlineWindow() }
        // The fitted path re-renders off `service.currentRecords` (the
        // `@ObservedObject` above) the moment a fit lands. An online gate's
        // data isn't in that dictionary — it's a disk read — so without this
        // the row stayed on its stale `.task`-time read: opening the gate's
        // detail (which fetches, saves, and pops back to this same
        // still-mounted row) never re-fired `.task`, and the card sat on
        // "fetched when connected" after the fetch had already landed.
        // `onlineFetchStamp` is the same "something changed, reload" signal
        // for the online-gate seam that `currentRecords` already is for the
        // fitted one.
        .onReceive(service.$onlineFetchStamp) { _ in refreshOnlineWindow() }
    }

    private func refreshOnlineWindow() {
        guard gate.isOnline else { return }
        onlineStore = ChsModelStore.loadOnline(gate.id)
    }

    private func pending(fitting: Bool = false, failed: Bool = false) -> ChsPendingCard {
        ChsPendingCard(name: gate.name, region: gate.region, id: gate.id, km: km,
                       status: cardStatus(id: gate.id, fitting: fitting, failed: failed))
    }

    /// The 7 online (fit-reject) gates: a covering fetched window
    /// reads like any other current card; without one, the pending shell
    /// carries the strip `onlineGateStatus` picks — never a queue status this
    /// gate can't be in.
    @ViewBuilder private var onlineCard: some View {
        let today = todayLocal(gate.tz)
        if let block = onlineStore?.block(covering: today) {
            OnlineGateCardView(gate: gate, window: block, km: km)
        } else {
            // Never fetched and fetched-but-run-out are different states and
            // print different strings (#93):
            // `onlineGateStatus` only null-checks `blocks.last` — nil is the
            // former (.notDownloaded), non-nil is the latter (.expired); it
            // doesn't read the block's own covered-to date.
            ChsPendingCard(name: gate.name, region: gate.region, id: gate.id, km: km,
                           status: onlineGateStatus(onlineStore?.blocks.last, online: net.online))
        }
    }
}

/// An online gate's list card with a covering fetched window: same shell and
/// reading treatment as `CurrentCardView`, off `ChsOnlineWindow.cardState`
/// instead of a `CurrentStationRecord` — this gate has no harmonic model to
/// build one from.
struct OnlineGateCardView: View {
    let gate: ChsCurrentGateInfo
    let window: ChsOnlineWindow
    var km: Double? = nil
    @AppStorage(speedUnitKey, store: AppGroup.defaults) private var speedUnit = "kn"

    private var state: CurrentCardState { window.cardState(at: appNow()) }

    var body: some View {
        let state = state
        StationCard(name: gate.name, region: gate.region, km: km,
                    detail: state.next.map { nextLine($0) }) {
            if currentPhase(signed: state.signed) == .slack {
                Text("SLACK")
                    .font(.caption2.monospaced().weight(.medium)).tracking(1)
                    .foregroundStyle(SN.navyDeep)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(SN.go, in: Capsule())
            } else {
                (Text(formatSpeed(abs(state.signed), unit: speedUnit))
                    .font(.largeTitle.monospacedDigit())
                 + Text(" \(speedUnitLabel(speedUnit))")
                    .font(.body))
                    .foregroundStyle(.white)
                // Direction-first (#59): a novice reads the arrow + cardinal;
                // the flood/ebb word demotes to a dimmer label. Kept as its
                // own Text — the screenshot tests match its exact label.
                let deg = state.signed >= 0 ? window.floodDirection : window.ebbDirection
                HStack(spacing: 4) {
                    CompassArrow(deg: deg).font(.caption2)
                    Text(compass16(deg)).font(.caption2)
                    Text(currentPhase(signed: state.signed).word).font(.caption2)
                        .foregroundStyle(SN.foam.opacity(0.6))
                }
                .foregroundStyle(SN.foam.opacity(0.9))
            }
        }
    }

    private func nextLine(_ next: CurrentEvent) -> String {
        let when = cardTime(next.time, gate.tz)
        return next.kind == .slack
            ? "Slack · \(when)"
            : "\(next.turnLabel) \(formatSpeed(abs(next.speed), unit: speedUnit)) \(speedUnitLabel(speedUnit)) · \(when)"
    }
}

/// The current-station card: same layout-A shell, but the reading is signed
/// velocity — speed + set arrow + Flooding/Ebbing, a Slack pill at slack, and
/// the next slack/max as the detail line (web StationCard's current layout).
struct CurrentCardView: View {
    let record: CurrentStationRecord
    var km: Double? = nil
    /// Set while this gate is showing its 60-day fast answer. On the LIST card
    /// that is the amber "Refining" strip and a `~` on the readings — nothing
    /// else. One marking per state (#93), and the strip carries the gate's own
    /// measured tolerance. The full explanation lives
    /// on the detail view's amber card.
    var provisional: ChsCurrentGateInfo? = nil
    @AppStorage(speedUnitKey, store: AppGroup.defaults) private var speedUnit = "kn"
    @State private var state: CurrentCardState?

    /// nil tolerance rather than the "±0 min" `provisionalTolerance` prints:
    /// a gate that never offered a fast answer has no measured number to show.
    private var status: CardStatus? {
        provisional.map {
            .refining(tolerance: $0.provisionalSlackMinutes == nil ? nil : $0.provisionalTolerance)
        }
    }

    /// A tilde marks the NUMBER itself as approximate rather than shouting
    /// around it; at normal card contrast "~5.8" reads cleanly.
    private var tilde: String { provisional == nil ? "" : "~" }

    var body: some View {
        StationCard(name: record.name, region: record.region, km: km,
                    detail: state?.next.map { nextLine($0) },
                    status: status) {
            if let state {
                let phase = currentPhase(signed: state.signed)
                if phase == .slack {
                    // SN.go, not a neutral chip — see the matching
                    // comment on ChsGateCardView's phase pill.
                    Text("SLACK")
                        .font(.caption2.monospaced().weight(.medium)).tracking(1)
                        .foregroundStyle(SN.navyDeep)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(SN.go, in: Capsule())
                } else {
                    (Text(tilde + formatSpeed(abs(state.signed), unit: speedUnit))
                        .font(.largeTitle.monospacedDigit())
                     + Text(" \(speedUnitLabel(speedUnit))")
                        .font(.body))
                        .foregroundStyle(.white)
                    // Direction-first (#59) — same treatment as
                    // OnlineGateCardView's, see the comment there.
                    let deg = record.setDegrees(signed: state.signed)
                    HStack(spacing: 4) {
                        CompassArrow(deg: deg).font(.caption2)
                        Text(compass16(deg)).font(.caption2)
                        Text(phase.word).font(.caption2)
                            .foregroundStyle(SN.foam.opacity(0.6))
                    }
                    .foregroundStyle(SN.foam.opacity(0.9))
                }
            }
        }
        .task { if state == nil { state = record.cardState(at: appNow()) } }
        // The refinement replaces the record under an open list: recompute.
        .onChange(of: record) { _, refined in state = refined.cardState(at: appNow()) }
    }

    private func nextLine(_ next: CurrentEvent) -> String {
        let when = cardTime(next.time, record.tz)
        return next.kind == .slack
            ? "\(tilde)Slack · \(when)"
            : "\(next.turnLabel) \(tilde)\(formatSpeed(abs(next.speed), unit: speedUnit)) \(speedUnitLabel(speedUnit)) · \(when)"
    }
}
