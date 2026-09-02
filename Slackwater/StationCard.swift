import SwiftUI
import TideEngine

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
    @State private var graph: StationCardGraph?

    var body: some View {
        StationCard(name: record.name, region: record.region, km: km, graph: graph) {
            if let state {
                ConditionsItem(reading: .tide(state, imperial: imperial))
            }
        }
        .task {
            if state == nil { state = record.cardState(at: appNow()) }
            if graph == nil { graph = record.cardGraph(at: appNow(), imperial: imperial) }
        }
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
        StationCard(name: gate.name, region: gate.region, km: km) {
            if let state {
                ConditionsItem(reading: .gate(state.phase))
                // A derived gate has no curve to carry the next slack, so
                // the card keeps its line (M46: pill + next slack).
                if let next = state.nextSlack {
                    Text("Slack · \(cardTime(next.time, gate.tz))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(SN.foam.opacity(0.92))
                }
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
                    graph: window.cardGraph(at: appNow(), unit: speedUnit)) {
            ConditionsItem(reading: .current(
                signed: state.signed,
                deg: state.signed >= 0 ? window.floodDirection : window.ebbDirection,
                unit: speedUnit))
        }
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
    @State private var graph: StationCardGraph?

    /// nil tolerance rather than the "±0 min" `provisionalTolerance` prints:
    /// a gate that never offered a fast answer has no measured number to show.
    private var status: CardStatus? {
        provisional.map {
            .refining(tolerance: $0.provisionalSlackMinutes == nil ? nil : $0.provisionalTolerance)
        }
    }

    var body: some View {
        StationCard(name: record.name, region: record.region, km: km,
                    status: status, graph: graph) {
            if let state {
                ConditionsItem(reading: .current(
                    signed: state.signed,
                    deg: record.setDegrees(signed: state.signed),
                    unit: speedUnit,
                    tilde: provisional != nil))
            }
        }
        .task {
            if state == nil { state = record.cardState(at: appNow()) }
            if graph == nil { graph = record.cardGraph(at: appNow(), unit: speedUnit, tilde: provisional != nil) }
        }
        // The refinement replaces the record under an open list: recompute.
        .onChange(of: record) { _, refined in
            state = refined.cardState(at: appNow())
            graph = refined.cardGraph(at: appNow(), unit: speedUnit, tilde: provisional != nil)
        }
    }
}

/// A clean semidiurnal sine for the preview cards. `phase` slides the wave
/// under the now mark (one swing in from the left edge): 2 puts extremes at
/// h ∈ {-5.1, 1.1, 7.3, 13.5}; 3.1 puts a crest exactly at now.
// One line so TypeScaleTests' enclosingDeclaration walk can own the
// formatter calls below (it only recognizes a declaration whose line ends
// with the opening brace).
private func previewGraph(scale: Double, offset: Double, includesZero: Bool, phase: Double = 2, label: (Double) -> String) -> StationCardGraph {
    let now = Date()
    let swing = StationCardGraph.swing / 3600  // hours between extremes
    let backH = StationCardGraph.backWindow / 3600
    let forwardH = StationCardGraph.forwardWindow / 3600
    func value(_ h: Double) -> Double { sin((h + phase) / swing * .pi) * scale + offset }
    let extremeHours = (-2...3).map { swing * (0.5 + Double($0)) - phase }
        .filter { (-backH...forwardH).contains($0) }
    // Analytic slack windows for the sine: |A·sin| = threshold solves to a
    // half-width of swing/π·asin(t/A) around each zero crossing. Spelled as
    // a plain loop with explicit types — the closure-chain form sent the
    // type-checker into the weeds.
    var windows: [WindowRun] = []
    if includesZero {
        let ratio: Double = min(1.0, defaultSlackThresholdKn / scale)
        let halfW: Double = swing / Double.pi * asin(ratio)
        for k in -1...3 {
            let z: Double = swing * Double(k) - phase
            guard z >= -backH, z <= forwardH else { continue }
            let start = now.addingTimeInterval((z - halfW) * 3600)
            let end = now.addingTimeInterval((z + halfW) * 3600)
            windows.append(WindowRun(start: start, end: end))
        }
    }
    return StationCardGraph(
        points: stride(from: -backH, through: forwardH, by: 0.25).map {
            .init(time: now.addingTimeInterval($0 * 3600), value: value($0))
        },
        extremes: extremeHours.map { h in
            let t = now.addingTimeInterval(h * 3600)
            return .init(time: t, value: value(h),
                         valueText: label(value(h)),
                         spokenText: label(value(h)),
                         timeText: cardTime(t, .current),
                         high: value(h) > offset,
                         // Signed preview curves are currents: opposing sets.
                         deg: includesZero ? (value(h) > offset ? 140 : 320) : nil)
        },
        now: now,
        includesZero: includesZero,
        windows: windows)
}

#Preview {
    ZStack {
        SN.canvas.ignoresSafeArea()
        ScrollView {
            VStack(spacing: 16) {
            StationCard(
                name: "Point Atkinson",
                region: "British Columbia",
                km: 12.4,
                graph: previewGraph(scale: 1.4, offset: 1.7, includesZero: false) {
                    "\(formatHeight($0, imperial: false)) m"
                }
            ) {
                ConditionsItem(reading: .tide(
                    CardState(height: 3.1, rising: true, next: nil),
                    imperial: false))
            }
            StationCard(
                name: "First Narrows",
                region: "Lions Gate Bridge",
                km: 8.7,
                graph: previewGraph(scale: 2.2, offset: 0, includesZero: true) {
                    "\(formatSpeed(abs($0), unit: "kn")) kn"
                }
            ) {
                ConditionsItem(reading: .current(signed: 1.0, deg: 140, unit: "kn"))
            }
            // Now exactly at a crest: the now dot and an extreme dot coincide.
            StationCard(
                name: "Tofino",
                region: "British Columbia",
                km: 41.2,
                graph: previewGraph(scale: 1.4, offset: 1.7, includesZero: false, phase: 3.1) {
                    "\(formatHeight($0, imperial: false)) m"
                }
            ) {
                ConditionsItem(reading: .tide(
                    CardState(height: 3.1, rising: false, next: nil),
                    imperial: false))
            }
            StationCard(
                name: "Active Pass",
                region: "British Columbia",
                km: 22.8,
                graph: previewGraph(scale: 2.2, offset: 0, includesZero: true, phase: 3.1) {
                    "\(formatSpeed(abs($0), unit: "kn")) kn"
                }
            ) {
                ConditionsItem(reading: .current(signed: 2.2, deg: 320, unit: "kn"))
            }
            StationCard(
                name: "Taumatawhakatangihangakoauauotamateaturipukakapikimaungahoronukupokaiwhenuakitanatahu",
                region: "Hawke's Bay",
                km: 12047.3
            ) {
                ConditionsItem(reading: .tide(
                    CardState(height: 1.2, rising: false, next: nil),
                    imperial: false))
            }
            StationCard(
                name: "Victoria Harbour",
                region: "British Columbia",
                status: .downloading,
                opacity: 0.82
            ) {
                EmptyView()
            }
            }
            .padding()
        }
    }
}

/// Where a fittable CHS station stands, in precedence order: what is happening
/// right now beats what is merely true. Replaces the five sentences
/// `chsPendingMessage` used to build.
@MainActor func cardStatus(id: String, fitting: Bool = false, failed: Bool = false) -> CardStatus {
    if fitting { return .downloading }
    if failed { return .failed }
    // Not in the download set at all (M53 — most of Canada). Opening it is what
    // downloads it, so this is the honest state connected or not; it must not
    // claim a queue it isn't in.
    if !ChsFitService.shared.isQueued(id) { return .notDownloaded }
    return Connectivity.shared.online ? .queued : .offline
}

/// The 7 online (fit-reject) gates: never queued, never fitted, so the only
/// question is what is on disk. Called with a window that does NOT cover the
/// strip on screen — a covering one renders as an ordinary reading.
///
/// Pure, and split from the view for it: the nil/stale distinction is the bug
/// #93 named, and it needs a test that doesn't build a card.
func onlineGateStatus(_ window: ChsOnlineWindow?, online: Bool) -> CardStatus {
    // Offline first: with no signal, neither tapping nor waiting fetches
    // anything, so "get online" is the only true thing to say.
    guard online else { return .offline }
    return window == nil ? .notDownloaded : .expired
}
