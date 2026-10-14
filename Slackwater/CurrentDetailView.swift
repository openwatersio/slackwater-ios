// Slackwater — GPL v3. Current detail: a continuous current-only strip
// beneath a fixed centerline, with a rolling schedule and paired tide link.
// Product contract: docs/scrubber.md.
import SwiftUI
import SlackwaterKit

/// One schedule for every real-velocity current strip (harmonic or fetched
/// official samples): slack rows bare, max rows with speed + set bearing.
func scheduleEntries(_ tl: TimelineData, floodDeg: Double, ebbDeg: Double, speedUnit: String) -> [ScheduleEntry] {
    // `scheduleRange` hangs off the ANCHOR, not `today` — the list a September
    // window shows is September's. Never re-derive it from `tl.today` here.
    let out: [ScheduleEntry] = tl.currentEvents
        .filter { tl.scheduleRange.contains($0.time) }
        .map { e in
            switch e.kind {
            case .slack:
                ScheduleEntry(time: e.time, pill: .slack)
            case .maxFlood:
                ScheduleEntry(time: e.time, pill: .flood,
                              value: "\(formatSpeed(abs(e.speed), unit: speedUnit)) \(speedUnitLabel(speedUnit))",
                              arrowDeg: floodDeg)
            case .maxEbb:
                ScheduleEntry(time: e.time, pill: .ebb,
                              value: "\(formatSpeed(abs(e.speed), unit: speedUnit)) \(speedUnitLabel(speedUnit))",
                              arrowDeg: ebbDeg)
            }
        }
    return out.sorted { $0.time < $1.time }
}

func subordinateCurrentFooter(stationName: String, referenceName: String) -> String {
    stationName == referenceName
        ? String(localized: "NOAA subordinate station: slacks and maxima, corrected by published offsets", comment: "Station provenance. Keep NOAA exact.")
        : String(localized: "NOAA subordinate station: \(referenceName)'s slacks and maxima, corrected by published offsets", comment: "Station provenance. The value is the reference-station name; keep NOAA exact.")
}

struct CurrentDetailView: View {
    let record: CurrentStationRecord
    @AppStorage(speedUnitKey, store: AppGroup.defaults) private var speedUnit = "kn"
    @AppStorage(AppGroup.slackWindowSpeedKey, store: AppGroup.defaults)
    private var slackWindowSpeed = defaultSlackThresholdKn
    @ObservedObject private var service = ChsFitService.shared

    @State private var live = appNow()
    @State private var scrubTime = Timeline.introStart(for: appNow())
    /// Chunk cache + merged window + governed y-scale (TimelineChunks.swift).
    @State private var store: TimelineWindowStore?
    /// The fortnight of maxima the Next max tile's mark and its sheet read.
    /// One scan per station, off the main actor — see `CurrentStandingStore`.
    @State private var standings = CurrentStandingStore()
    /// The local midnight the schedule week hangs from. `returnToNow`, the
    /// picker, and the settle-follow below move it.
    @State private var anchor = Date.distantPast
    @State private var viewportPts: CGFloat = 0
    /// This gate's stored model, for the station details' fit rows — how many
    /// days it was fitted from and when that download happened. Re-read
    /// whenever the record changes, since a refinement replaces both.
    @State private var chsModel: ChsModel?
    /// The nearest tide-series station inside `nearbyStationRadiusKm` — the
    /// discovery fallback when no curated `tideReference` pairs this station.
    /// Computed once on appear; the body re-evaluates on every scrub tick.
    @State private var nearbyTide: (item: StationItem, km: Double)?
    private var timeline: TimelineData? { store?.timeline }

    /// The gate identity behind a provisional fast answer — nil for a final
    /// model, which is what every readout below keys on.
    private var provisionalGate: ChsCurrentGateInfo? {
        service.isProvisional(record.id) ? record.chsGate : nil
    }

    private var pairedTide: TideStationRecord? { record.pairedTide }
    private var tz: TimeZone { record.tz }
    /// Engine-exact velocity under the centerline, the same call the
    /// committed readout has always made.
    private func lead(_ tl: TimelineData, ink: Color = .white) -> CurrentLead {
        var l = CurrentLead(timeline: tl, scrubTime: scrubTime, now: live, signed: exactSigned(at: scrubTime),
                            floodDeg: record.floodDirection, ebbDeg: record.ebbDirection,
                            speedUnit: speedUnit, tz: tz, ink: ink, provisional: provisionalGate != nil)
        // The tile ranks the maximum it prints, against its own direction's.
        l.standing = l.nextMaxEvent.flatMap {
            standings.standing(speed: $0.speed, time: $0.time, kind: $0.kind)
        }
        return l
    }

    var body: some View {
        let sky = SkyState(time: scrubTime, latitude: record.latitude, longitude: record.longitude,
                           days: timeline?.days ?? [],
                           eclipses: timeline?.eclipses ?? [])
        ScrubDetailScaffold(name: record.name, region: record.region,
                            favoriteId: record.itemId, tz: tz,
                            timeline: timeline,
                            entries: { scheduleEntries($0, floodDeg: record.floodDirection,
                                                       ebbDeg: record.ebbDirection, speedUnit: speedUnit) },
                            scrubTime: $scrubTime,
                            anchor: $anchor,
                            onPicked: { picked in store?.jump(to: scrubTime, anchor: picked) },
                            topBackdrop: AnyView(SkyBackdrop(sky: sky)),
                            alertOffer: currentAlertOffer(
                                // CurrentLead's `atMax`, read here because the lead keeps it private.
                                maxIsFlood: timeline?.currentEvents.first {
                                    $0.kind != .slack && abs($0.time.timeIntervalSince(scrubTime)) < 1
                                }.map { $0.kind == .maxFlood },
                                onEclipseContact: isOnEclipseContact(scrubTime, timeline?.eclipses ?? [])),
                            above: { EmptyView() },
                            card: { tl in
                                CurrentScrubCard(lead: lead(tl, ink: sky.ink), data: tl,
                                                 speedUnit: speedUnit, now: live,
                                                 floodDeg: record.floodDirection, ebbDeg: record.ebbDirection,
                                                 sky: sky,
                                                 scrubTime: $scrubTime, onReturn: returnToNow,
                                                 onResumeScrubbedAway: { live = appNow() },
                                                 scale: store?.scale,
                                                 scrollGate: store?.gate,
                                                 onViewportWidth: { viewportPts = $0 })
                            },
                            links: { tl, jump in
                                VStack(spacing: 12) {
                                    if let gate = provisionalGate {
                                        ChsDownloadNotice(stationID: gate.id, tz: tz, gate: gate)
                                    }
                                    SummaryTiles(primary: lead(tl).nextMax,
                                                 primaryDetail: maxDetail(tl, jump: jump),
                                                 primarySymbol: maxSymbol(tl),
                                                 primaryValueColor: provisionalGate != nil ? SN.amber : .white,
                                                 moon: sky.illumination,
                                                 at: scrubTime,
                                                 eclipse: tl.eclipses.first { $0.underway(at: scrubTime) },
                                                 solarEclipse: tl.solarEclipses.first { $0.underway(at: scrubTime) },
                                                 solarObscuration: sky.obscuration,
                                                 onJump: jump,
                                                 latitude: record.latitude, longitude: record.longitude)
                                    StationLinksRow(stationId: record.itemId) {
                                        if let port = pairedTide {
                                            TideAtPortLink(port: port)
                                        } else if let nearby = nearbyTide {
                                            NearbyStationLink(item: nearby.item, km: nearby.km)
                                        }
                                    }
                                }
                            },
                            bottom: {
                                VStack(spacing: 14) {
                                    footer
                                    stationDetails
                                }
                            })
            .onAppear {
                if store == nil {
                    // A shared link that landed first has placed the anchor and
                    // the scrub (ScrubDetailScaffold.jump): open on its moment,
                    // or the first build covers now and the strip clamps it away.
                    let linked = anchor != .distantPast
                    if !linked { anchor = todayLocal(tz) }
                    resetStore(focus: linked ? scrubTime : nil)
                }
                RecentsStore.shared.record(record.itemId)
                if record.isChs { chsModel = ChsModelStore.loadCurrent(record.id) }
                if pairedTide == nil, nearbyTide == nil,
                   let n = StationItem.nearest(.tide, toLat: record.latitude, lon: record.longitude),
                   n.km <= nearbyStationRadiusKm {
                    nearbyTide = n
                }
            }
            .onChange(of: scrubTime) { _, t in store?.focus(t, viewportPts: viewportPts) }
            // The schedule follows a scrub that has settled outside its window —
            // the strip is endless now. A cancelled sleep is a scrub still in
            // motion, same rest rule as the chrome row's.
            .task(id: scrubTime) {
                guard (try? await Task.sleep(for: .milliseconds(600))) != nil else { return }
                // `Timeline.window`, not `scheduleRange`: the look-back is this anchor's own ink.
                if let tl = timeline,
                   let next = Timeline.reanchor(settledAt: scrubTime, anchor: tl.anchor, tz: tz) {
                    anchor = next
                    store?.setAnchor(anchor)
                }
            }
            // The refinement lands under an open page: same station, new model. The
            // curve, the schedule and the amber marking all have to follow it —
            // a fresh store, parked where the scrub already is.
            .onChange(of: record) { _, r in
                resetStore(focus: scrubTime)
                if r.isChs { chsModel = ChsModelStore.loadCurrent(r.id) }
            }
            .onChange(of: slackWindowSpeed) { _, _ in resetStore(focus: scrubTime) }
            // After the strip, never before it: the scan only feeds a tile
            // caption and the sheet behind it, and the curve is what the
            // reader is waiting for.
            .task(id: record.id) {
                await standings.load(record: record, around: live)
                // The year costs about a second and only the sheet shows it.
                await standings.loadYear(record: record, around: live)
            }
    }

    // MARK: - Colour

    /// Kept as the tests' named binding (ColourAndFormTests); the palette
    /// itself lives in `StationGlyph.colour(for:)`. Slack is the app's "go"
    /// colour — the moment the app is named for, the same on every surface.
    static func phaseColor(_ phase: CurrentPhase) -> Color {
        StationGlyph.colour(for: phase == .flood ? .flood : phase == .ebb ? .ebb : .slack)
    }

    private var footer: some View {
        DetailFooter(stationID: record.itemId, scrubTime: scrubTime, tz: tz) {
            if record.isChs {
                // Same register as the CHS tide footer (TideDetailView).
                Text("Downloaded from CHS (IWLS), then fitted and computed on this device. These are not CHS-published predictions. Flood sets \(Int(record.floodDirection.rounded()))°T.")
                    .font(.caption2).foregroundStyle(SN.foam.opacity(0.3))
                    .multilineTextAlignment(.center)
            } else if let ref = record.referenceRecord {
                // A different accuracy class: NOAA's table offsets against the
                // reference's events, with a drawn curve between them.
                Text("\(subordinateCurrentFooter(stationName: record.name, referenceName: ref.name)). Flood sets \(Int(record.floodDirection.rounded()))°T.")
                    .font(.caption2).foregroundStyle(SN.foam.opacity(0.3))
                    .multilineTextAlignment(.center)
            } else {
                Text("NOAA harmonic current prediction. Flood sets \(Int(record.floodDirection.rounded()))°T. Speeds use \(speedUnit == "kn" ? "knots" : speedUnitLabel(speedUnit)).")
                    .font(.caption2).foregroundStyle(SN.foam.opacity(0.3))
            }
        }
    }

    /// The nod to the nerds (#170): the axis, the net flow the fit found under
    /// the tide, and — for a subordinate — NOAA's table itself. Collapsed, so
    /// none of it costs the reader who only wants the next slack anything.
    private var stationDetails: some View {
        StationDetails {
            StationDetailRow("Station", record.id)
            StationDetailRow("Position", formatCoord(lat: record.latitude, lon: record.longitude))
            StationDetailRow("Time zone", record.timezone)
            StationDetailRow("Flood sets", "\(Int(record.floodDirection.rounded()))°T")
            StationDetailRow("Ebb sets", "\(Int(record.ebbDirection.rounded()))°T")
            // Z0 belongs to a harmonic fit. A subordinate has no fit of its
            // own — its record carries no meaningful mean flow to report.
            if !record.isSubordinate {
                StationDetailRow("Mean flow", record.detailsMeanFlow(unit: speedUnit))
                StationDetailNote("Mean flow is the net drift remaining after the tide averages out.")
            }
            if let ref = record.referenceRecord {
                StationDetailRow("Reference", "\(ref.name), \(Int(distanceKm(record.latitude, record.longitude, ref.latitude, ref.longitude).rounded())) km away")
            }
            StationDetailRow("Prediction", record.detailsPrediction)
            if let offsets = record.detailsOffsets {
                StationDetailRow("Time offsets", offsets.times)
                StationDetailRow("Speed ratios", offsets.ratios)
            }
            if let model = chsModel {
                // The model's own window, not the gate's target: a provisional
                // fit is 60 days of a gate whose final window is 210.
                StationDetailRow("Fit window", "\(Int(model.fitDays ?? record.chsGate?.fitDays ?? 0)) days of CHS observations")
                HStack(alignment: .firstTextBaseline) {
                    Text("Data downloaded")
                    Spacer()
                    Text(model.fittedAt, style: .relative)
                }
                .font(.caption)
            }
        }
    }

    // MARK: - Data

    /// Engine-exact signed velocity — same call as the old committed readout.
    private func exactSigned(at t: Date) -> Double {
        record.engineStation.speeds(from: t, to: t.addingTimeInterval(1), step: 1).first?.speed ?? 0
    }

    private func returnToNow() {
        live = appNow()
        // The anchor too: return-to-now from a September window has to bring
        // the whole schedule week back. The scrubber rides home animated
        // within `Timeline.snapJumpHours` and lands unanimated past it.
        anchor = todayLocal(tz)
        store?.jump(to: live, anchor: anchor)
        scrubTime = live
    }

    /// One place the store is created from, so the record and the slack
    /// threshold can never be applied by two different code paths. `focus`
    /// The Next max tile's sheet, where there is a fortnight to rank against.
    /// An online gate never has one, so its tile stays inert as before.
    private func maxDetail(_ tl: TimelineData, jump: @escaping (Date) -> Void) -> (() -> AnyView)? {
        let l = lead(tl)
        guard let standing = l.standing, let e = l.nextMaxEvent, let value = l.nextMax?.value
        else { return nil }
        let place = record.name, months = standings.months(e.kind), tz = tz, now = live
        let windows = tl.slackWindows
        let direction = e.kind == .maxFlood
            ? String(localized: "Flood", comment: "Current direction, used in a sentence.")
            : String(localized: "Ebb", comment: "Current direction, used in a sentence.")
        return {
            AnyView(MaxDetailSheet(value: value, direction: direction, place: place,
                                   standing: standing, months: months,
                                   slackWindows: windows, maximumAt: e.time,
                                   tz: tz, now: now, onJump: jump))
        }
    }

    /// A span glyph on a marked tile, the same sense the Range tile uses: the
    /// mark is about size, not about which way the water is going.
    private func maxSymbol(_ tl: TimelineData) -> String? {
        lead(tl).standing?.marks == true ? "arrow.up.and.down" : nil
    }

    /// nil opens around now (the intro); a focus keeps a parked scrub parked.
    private func resetStore(focus: Date?) {
        let s = TimelineWindowStore(source: .current(record, threshold: normalizedSlackThresholdKn(slackWindowSpeed)))
        s.start(anchor: anchor, now: live, focus: focus)
        store = s
    }
}

#Preview {
    NavigationStack {
        CurrentDetailView(record: CurrentStationRecord.all.first { $0.name == "Deception Pass (Narrows)" }!)
    }
}
