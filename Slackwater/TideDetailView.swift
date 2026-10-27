// Slackwater — GPL v3. Tide detail: a continuous strip beneath a fixed
// centerline and a rolling schedule anchored to the selected local week.
// Scrubber behavior here is specified in docs/scrubber.md: update the spec in the same change as any visible change.
import SwiftUI
import SlackwaterKit

struct TideDetailView: View {
    let record: TideStationRecord
    var preview: ChsTidePreview? = nil
    @AppStorage(unitsKey, store: AppGroup.defaults) private var units = heightUnits()

    @State private var live = appNow()
    /// The single scrub time — whatever sits under the centerline.
    @State private var scrubTime = Timeline.introStart(for: appNow())
    /// Chunk cache + merged window + governed y-scale (TimelineChunks.swift).
    @State private var store: TimelineWindowStore?
    /// The ±15-day scan the Range tile's mark and its sheet both read. One per
    /// station, loaded off the main actor, deliberately not re-anchored by the
    /// scrub — see `TideStandingStore`.
    @State private var standings = TideStandingStore()
    @State private var previewTimeline: TimelineData?
    @State private var displayedPreview: ChsTidePreview?
    @State private var previewGate = ScrollGate()
    @State private var chsFittedAt: Date?
    /// The nearest current-series station inside `nearbyStationRadiusKm`, or
    /// nil. Computed once on appear — a catalog scan has no place in a body
    /// that re-evaluates on every scrub tick.
    @State private var nearbyCurrent: (item: StationItem, km: Double)?
    /// The local midnight the schedule week hangs from. `returnToNow`, the
    /// range bar's picker, and the settle-follow below move it.
    @State private var anchor = Date.distantPast
    /// The strip viewport's width, reported by the strip — the span the
    /// scale governor fits the curve against.
    @State private var viewportPts: CGFloat = 0
    /// Bumped when a preview clamp moves the selection, so the strip moves for it.
    @State private var clampRequests = 0
    /// The Range bars' week: the local midnight `RangeOutlook.week` moves.
    @State private var outlookWeek: Date?
    /// The opening slide, Now, and a picked date ride the strip through days
    /// on the way to a week already chosen for them; the bars ignore the ride
    /// until the scrub next rests.
    @State private var outlookHeld = true

    private var timeline: TimelineData? { store?.timeline ?? previewTimeline }
    private var activePreview: ChsTidePreview? { store == nil ? preview ?? displayedPreview : nil }

    private var imperial: Bool { units == "imperial" }
    private var tz: TimeZone { record.tz }
    private var unit: String { heightUnit(imperial: imperial) }
    private var scrubHeight: Double { exactHeight(at: scrubTime) }
    private var nextExtreme: TideExtreme? {
        timeline?.tideExtremes.first { $0.time > scrubTime }
    }
    private var rising: Bool {
        if let preview = activePreview { return preview.rateOfChange(at: scrubTime) >= 0 }
        return nextExtreme.map { $0.kind == .high } ?? true
    }
    private var prevExtreme: TideExtreme? {
        timeline?.tideExtremes.last { $0.time <= scrubTime }
    }
    /// Metres per hour under the centerline, signed.
    private var scrubRate: Double { timeline?.rateAt(scrubTime) ?? 0 }
    /// The rate ramp's colour when the rate is out of the ordinary (#95: at
    /// Friday Harbor 0.8 ft/hr is nothing, at Ile Haute 8 ft/hr is the
    /// warning), else nil and the direction colour stands. The lead's word
    /// and glyph wear it for the selection's rate, the pill for the peak it
    /// names, lifted for the sky they float on — the ramp's red end is
    /// unreadable against a sunrise otherwise.
    private func rateWarning(_ rate: Double, over ground: UInt32) -> Color? {
        abs(rate) >= tideMovementRampAnchorsMHr[0]
            ? SN.speedLabelColour(Timeline.rampT(forTideRateMHr: abs(rate)), over: ground) : nil
    }
    /// "Rising 2.3 ft/hr" in place of the lead's bare word while the water is
    /// fast: it explains the yellow line under it.
    private var leadRate: String? {
        atTurn == nil ? tideRateReading(rate: scrubRate, imperial: imperial) : nil
    }
    /// The stop the pill names and its tap walks to: the next turn, a fast
    /// run's peak before it, or the sun's next rise or set when that comes
    /// first.
    private var nextStop: CommentaryStop? {
        guard let timeline else { return nil }
        return nextCommentaryStop(tideWaterStop(in: timeline, after: scrubTime),
                                  sun: timeline.days, after: scrubTime, drawn: timeline.drawnSpan)
    }
    private var commentary: CommentaryContent? {
        nextStop.map { commentaryContent($0, from: scrubTime) }
    }
    /// The fast-run peak the pill names, if that is its stop: the pill still
    /// leads to a warning, so it wears the peak's ramp colour.
    private var commentaryPeak: TideRatePoint? {
        guard let timeline, let stop = nextStop else { return nil }
        return tideFlowArrows(timeline.tideRates).first { $0.time == stop.time }
    }
    private func scrubToCommentary() {
        guard let target = nextStop?.time else { return }
        scrubTime = target
    }

    var body: some View {
        let sky = SkyState(time: scrubTime, latitude: record.latitude, longitude: record.longitude,
                           days: timeline?.days ?? [],
                           eclipses: timeline?.eclipses ?? [])
        ScrubDetailScaffold(name: record.name, region: record.region,
                            favoriteId: record.id, tz: tz,
                            timeline: timeline, entries: scheduleEntries,
                            scrubTime: $scrubTime,
                            anchor: $anchor,
                            canPickDate: activePreview == nil,
                            onPicked: { picked in
                                if let coverage = activePreview?.coverage {
                                    anchor = todayLocal(tz)
                                    clamp(into: coverage)
                                } else { store?.jump(to: scrubTime, anchor: picked) }
                                holdOutlook(anchor)
                            },
                            topBackdrop: AnyView(SkyBackdrop(sky: sky)),
                            alertOffer: activePreview == nil ? tideAlertOffer(
                                scrubbedAway: scrubbedAway(scrubTime, from: live),
                                turnIsHigh: atTurn.map { $0.kind == .high },
                                onEclipseContact: isOnEclipseContact(scrubTime, timeline?.eclipses ?? []),
                                heightM: scrubHeight, rising: rising, imperial: imperial) : nil,
                            above: { EmptyView() },
                            card: { tl in
                                let geo = TimelineGeo(data: tl, scale: store?.scale)
                                TimelineScrubStrip(data: tl, geo: geo,
                                                   imperial: imperial, now: live,
                                                   chromeInk: sky.ink,
                                                   scrubTime: $scrubTime,
                                                   onReturn: returnToNow,
                                                   onResumeScrubbedAway: { live = appNow() },
                                                   spokenLead: spokenLead,
                                                   commentary: commentary,
                                                   commentaryTint: commentaryPeak.flatMap { rateWarning($0.rate, over: sky.chromeGround) },
                                                   onCommentary: scrubToCommentary,
                                                   scrollGate: store?.gate ?? previewGate,
                                                   onViewportWidth: { viewportPts = $0 },
                                                   moveRequests: clampRequests)
                                    .overlay(alignment: .top) { lead(sky: sky) }
                            },
                            links: { tl, jump in
                                VStack(spacing: 12) {
                                    if let coverage = activePreview?.coverage {
                                        ChsDownloadNotice(stationID: record.id, end: coverage.upperBound, tz: tz)
                                    }
                                    SummaryTiles(primary: range,
                                                 primaryDetail: rangeDetail(jump: jump),
                                                 primaryOutlook: AnyView(RangeOutlook(timeline: tl,
                                                     week: outlookWeek ?? dayLocal(scrubTime, tz), at: scrubTime)),
                                                 primarySymbol: rangeSymbol,
                                                 moon: sky.illumination, at: scrubTime, sunDays: tl.days,
                                                 moonAngle: sky.moonLightAngle,
                                                 eclipse: tl.eclipses.first { $0.underway(at: scrubTime) },
                                                 solarEclipse: tl.solarEclipses.first { $0.underway(at: scrubTime) },
                                                 solarObscuration: sky.obscuration,
                                                 onJump: jump,
                                                 latitude: record.latitude, longitude: record.longitude)
                                    StationLinksRow(stationId: record.id) {
                                        if let nearby = nearbyCurrent {
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
                let linked = anchor != .distantPast
                if anchor == .distantPast { anchor = todayLocal(tz) }
                // Not the scrub's day: the opening slide starts two hours back, which after midnight is yesterday.
                if outlookWeek == nil { outlookWeek = linked ? dayLocal(scrubTime, tz) : todayLocal(tz) }
                if preview == nil, store == nil {
                    let s = TimelineWindowStore(source: .tide(record))
                    s.start(anchor: anchor, now: live, focus: linked ? scrubTime : FoldHandoff.pending(record.id))
                    store = s
                }
                RecentsStore.shared.record(record.id)
                if record.isChs {
                    chsFittedAt = ChsModelStore.load(record.id)?.fittedAt
                }
                if nearbyCurrent == nil,
                   let n = StationItem.nearest(.current, toLat: record.latitude, lon: record.longitude),
                   n.km <= nearbyStationRadiusKm {
                    nearbyCurrent = n
                }
            }
            .task(id: preview?.fetchedAt) {
                if anchor == .distantPast { anchor = todayLocal(tz) }
                if let preview, let coverage = preview.coverage {
                    displayedPreview = preview
                    anchor = todayLocal(tz)
                    clamp(into: coverage)
                    let record = record, now = live, day = anchor
                    let built = await Task.detached(priority: .userInitiated) {
                        TimelineData.build(preview: preview, tide: record, now: now, anchor: day)
                    }.value
                    guard !Task.isCancelled else { return }
                    previewTimeline = built
                } else if store == nil {
                    while !previewGate.isQuiet {
                        guard (try? await Task.sleep(for: .milliseconds(50))) != nil else { return }
                    }
                    guard !Task.isCancelled else { return }
                    let s = TimelineWindowStore(source: .tide(record))
                    s.start(anchor: anchor, now: live, focus: scrubTime)
                    store = s
                    previewTimeline = nil
                    chsFittedAt = record.isChs ? ChsModelStore.load(record.id)?.fittedAt : nil
                }
                // After the timeline, never before it: the strip is what the
                // reader is waiting for, and this scan only feeds a tile
                // caption and the sheet behind it.
                await standings.load(record: record, around: live)
                // The year costs about a second and only the sheet shows it,
                // so it comes after the fortnight and never blocks the strip.
                await standings.loadYear(record: record, around: live)
            }
            .onChange(of: scrubTime) { _, t in
                if !outlookHeld { outlookWeek = RangeOutlook.week(from: outlookWeek, scrub: t, tz: tz) }
                if let coverage = activePreview?.coverage {
                    clamp(into: coverage)
                } else { store?.focus(t, viewportPts: viewportPts) }
            }
            .onChange(of: live) { _, now in
                store?.setNow(now)
                // A preview is built once per fetch, so only a rebuild relabels its days.
                guard store == nil, let preview = displayedPreview, let built = previewTimeline,
                      built.today != dayLocal(now, tz) else { return }
                let record = record, day = built.anchor
                Task {
                    let relabelled = await Task.detached(priority: .userInitiated) {
                        TimelineData.build(preview: preview, tide: record, now: now, anchor: day)
                    }.value
                    if let relabelled, previewTimeline?.revision == built.revision { previewTimeline = relabelled }
                }
            }
            // The schedule follows a scrub that has settled somewhere outside
            // its window — the strip is endless now, and a list still describing
            // three weeks ago would be a lie. A cancelled sleep is a scrub
            // still in motion, same rest rule as the chrome row's.
            .task(id: scrubTime) {
                guard (try? await Task.sleep(for: .milliseconds(600))) != nil else { return }
                if outlookHeld {
                    outlookHeld = false
                    outlookWeek = RangeOutlook.week(from: outlookWeek, scrub: scrubTime, tz: tz)
                }
                guard activePreview == nil else { return }
                // `Timeline.window`, not `scheduleRange`: the look-back is this anchor's own ink.
                if let tl = timeline,
                   let next = Timeline.reanchor(settledAt: scrubTime, anchor: tl.anchor, tz: tz) {
                    anchor = next
                    store?.setAnchor(anchor)
                }
            }
    }

    // MARK: - The lead reading, fixed over the centerline

    /// At a turn the water is at its high or low; otherwise it is on its way
    /// to one. Snap targets land exactly on the extreme, hence the 1 s.
    private var atTurn: TideExtreme? {
        timeline?.tideExtremes.first { abs($0.time.timeIntervalSince(scrubTime)) < 1 }
    }
    /// This swing's range: the extreme behind the scrub to the one ahead.
    private var range: (label: String, value: String, caption: String)? {
        guard let prev = prevExtreme, let next = nextExtreme else { return nil }
        return (String(localized: "Range", comment: "Tide-range summary label."),
                "\(formatHeight(abs(next.height - prev.height), imperial: imperial)) \(unit)",
                // One line, three claimants: `rangeCaption` owns the order.
                rangeCaption(record: record, swing: swingStanding, direction: rangeDirection))
    }

    /// Where THIS SWING sits among the fortnight's swings. The tile prints a
    /// swing, so the tile's mark ranks a swing: a station can have a big range
    /// on a day whose low is unremarkable, and ranking the level on a tile
    /// whose value is a range read as a conflation on screen.
    private var swingStanding: PeakStanding? {
        guard let prev = prevExtreme, let next = nextExtreme else { return nil }
        return standings.swing(abs(next.height - prev.height), time: next.time)
    }

    /// Where the turn ahead sits between the station's own floor and ceiling.
    /// A different question from the swing's, and it belongs to the sheet's
    /// max/min section rather than to the tile.
    private var standing: TideStanding? {
        nextExtreme.flatMap(standings.standing(at:))
    }

    /// The glyph beside the tile's label. A calendar where the water follows a
    /// year, otherwise a to-bar arrow for a marked turn — the same `⤒`/`⤓`
    /// sense the tile's own value carries: a swing is a distance between two
    /// turns, not a direction of travel.
    ///
    /// Seasonal outranks the mark here for the reason it outranks it in the
    /// caption: it changes how the whole screen should be read.
    private var rangeSymbol: String? {
        if record.seasonalRatio != nil { return "calendar" }
        guard let swingStanding, swingStanding.marks else { return nil }
        return "arrow.up.and.down"
    }

    /// Which way this swing runs, when there is nothing more pressing to say.
    private var rangeDirection: String {
        prevExtreme?.kind == .low
            ? String(localized: "low to high", comment: "Tide-range direction.")
            : String(localized: "high to low", comment: "Tide-range direction.")
    }

    /// The Range tile's sheet. It opens wherever there is something behind the
    /// number: a fortnight to rank this swing against, or water that follows a
    /// year. A station with neither keeps the inert tile it had.
    private func rangeDetail(jump: @escaping (Date) -> Void) -> (() -> AnyView)? {
        guard let range, record.seasonalRatio != nil || swingStanding != nil else { return nil }
        let place = record.name, ratio = record.seasonalRatio
        let standing = standing, swing = swingStanding, record = record
        let months = standings.months
        let phases = swing.map { SwingFigure.moonPhases(in: $0.window) } ?? []
        let seasons = YearFigure.seasonsAround(TideStanding.yearWindow(around: live, tz: record.tz), tz: record.tz)
        let imperial = imperial, unit = unit, now = live
        return {
            AnyView(RangeDetailSheet(
                value: range.value, direction: self.rangeDirection,
                seasonalRatio: ratio, place: place,
                standing: standing, swing: swing, phases: phases, months: months, seasons: seasons,
                latDatum: record.latDatum, hatDatum: record.hatDatum,
                imperial: imperial, unit: unit, tz: record.tz, now: now, onJump: jump))
        }
    }

    private var leadState: String {
        atTurn.map {
            $0.kind == .high
                ? String(localized: "High", comment: "High-tide state.")
                : String(localized: "Low", comment: "Low-tide state.")
        } ?? (rising
            ? String(localized: "Rising", comment: "Rising-tide state.")
            : String(localized: "Falling", comment: "Falling-tide state."))
    }
    /// The lead in words, for the strip's spoken value.
    private var spokenLead: String {
        let reading = spokenReading(leadState, formatHeight(scrubHeight, imperial: imperial), unit: unit)
        return leadRate == nil ? reading : spokenTideRate(after: reading, rate: scrubRate, imperial: imperial)
    }

    private func lead(sky: SkyState) -> some View {
        let ink = sky.ink
        let turn = atTurn
        let up = turn.map { $0.kind == .high } ?? rising
        let state = leadRate ?? leadState
        let warning = rateWarning(scrubRate, over: sky.chromeGround)
        return LeadCard(value: formatHeight(scrubHeight, imperial: imperial),
                        unit: unit,
                        time: leadWhen(scrubTime, tz),
                        valueColor: ink,
                        timeColor: ink) {
            // Word then glyph, the order the current lead reads in.
            // The rate, when it shows, outranks the word's usual ink (#95).
            Text(state).fontWeight(.medium).monospacedDigit()
                .foregroundStyle(leadRate == nil ? ink.opacity(0.85) : warning ?? ink)
                .accessibilityLabel(leadRate == nil ? leadState
                                    : spokenTideRate(after: leadState, rate: scrubRate, imperial: imperial))
            // The graph's own two inks, so the eyebrow names the curve the
            // reader is looking at — unless the rate is out of the ordinary
            // (#95), which outranks direction.
            LeadGlyph(systemName: turn.map { $0.kind == .high ? "arrow.up.to.line" : "arrow.down.to.line" }
                                  ?? (rising ? "arrow.up.right" : "arrow.down.right"))
                .foregroundStyle(warning ?? (up ? SN.graphHigh : SN.graphLow))
        }
    }

    // MARK: - Rolling multi-day schedule (turns, day-grouped)

    private func scheduleEntries(_ tl: TimelineData) -> [ScheduleEntry] {
        tl.tideExtremes
            .filter { tl.scheduleRange.contains($0.time) }
            .map { ScheduleEntry(time: $0.time, pill: $0.kind == .high ? .high : .low,
                                 value: "\(formatHeight($0.height, imperial: imperial)) \(unit)") }
            .sorted { $0.time < $1.time }
    }

    // The provenance/confidence marking (chs-online spec §2d, §7d — simplified
    // to plain language, design pass M4.3): lead with where the data came
    // from, keep the honesty clause that the numbers are device-computed. The
    // full clause-10 licence statement carries its weight in Settings.
    private var footer: some View {
        DetailFooter(stationID: record.id, scrubTime: scrubTime, tz: tz) {
            if activePreview != nil {
                Text("Official CHS tide predictions, downloaded to this device. Heights are above LLWLT chart datum.")
                    .font(.caption2).foregroundStyle(SN.foam.opacity(0.3))
                    .multilineTextAlignment(.center)
            } else if record.isChs {
                Text("\(record.chartDatum) chart datum. Downloaded from CHS (IWLS), then fitted and computed on this device. These are not CHS-published predictions.")
                    .font(.caption2).foregroundStyle(SN.foam.opacity(0.3))
                    .multilineTextAlignment(.center)
            } else if let ref = record.referenceRecord {
                // A different accuracy class, and the reference can be far
                // away (Nurse Channel sits 600 km from Settlement Point).
                Text("\(record.chartDatum) chart datum. Based on \(ref.name) tides and NOAA's published offsets; computed on this device.")
                    .font(.caption2).foregroundStyle(SN.foam.opacity(0.3))
                    .multilineTextAlignment(.center)
            } else if record.id.hasPrefix("noaa/") {
                Text("\(record.chartDatum) chart datum. NOAA harmonic prediction.")
                    .font(.caption2).foregroundStyle(SN.foam.opacity(0.3))
            } else if let source = record.source {
                // Kartverket's terms ask to be named wherever its data is used.
                Text("\(record.chartDatum) chart datum. Harmonic constants from \(source).")
                    .font(.caption2).foregroundStyle(SN.foam.opacity(0.3))
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var stationDetails: some View {
        StationDetails {
            StationDetailRow("Datum", record.detailsDatum)
            StationDetailNote("Heights are measured from chart datum. A negative value predicts less water than the charted depth.")
            StationDetailRow("Station", record.id)
            StationDetailRow("Position", formatCoord(lat: record.latitude, lon: record.longitude))
            StationDetailRow("Time zone", record.timezone)
            if activePreview != nil {
                StationDetailRow("Prediction", String(localized: "Official CHS predictions"))
            } else if let ref = record.referenceRecord {
                StationDetailRow("Reference", "\(ref.name), \(Int(distanceKm(record.latitude, record.longitude, ref.latitude, ref.longitude).rounded())) km away")
                StationDetailRow("Prediction", "NOAA reference highs and lows, adjusted by published offsets and computed on this device")
            } else {
                StationDetailRow("Prediction", "\(record.constituents.count) harmonic constituents computed on this device")
            }
            if let chsFittedAt {
                HStack(alignment: .firstTextBaseline) {
                    Text("Data downloaded")
                    Spacer()
                    Text(chsFittedAt, style: .relative)
                }
                .font(.caption)
            }
        }
    }

    // MARK: - Data

    /// Engine-exact height — the same call the old model's committed readout
    /// made, so the now-readout is unchanged by the scrub rework.
    private func exactHeight(at t: Date) -> Double {
        if let preview = activePreview { return preview.height(at: t) ?? 0 }
        return record.engineStation.heights(from: t, to: t.addingTimeInterval(1), step: 1).first?.height ?? 0
    }

    private func clamp(into coverage: ClosedRange<Date>) {
        let clamped = min(max(scrubTime, coverage.lowerBound), coverage.upperBound)
        guard clamped != scrubTime else { return }
        clampRequests += 1
        scrubTime = clamped
    }

    private func returnToNow() {
        live = appNow()
        // The anchor too: return-to-now from a September window has to bring
        // the whole schedule week back, not just park the centerline. The
        // strip itself rides home animated within `Timeline.snapJumpHours`
        // and lands unanimated past it — the scrubber decides by distance;
        // the store only guarantees now's chunks exist.
        anchor = todayLocal(tz)
        holdOutlook(anchor)
        store?.jump(to: live, anchor: anchor)
        if let coverage = activePreview?.coverage {
            scrubTime = min(max(live, coverage.lowerBound), coverage.upperBound)
        } else { scrubTime = live }
    }

    private func holdOutlook(_ week: Date) {
        outlookWeek = week
        outlookHeld = true
    }
}

/// Progress stays local to this notice so each downloaded chunk does not rebuild the timeline.
struct ChsDownloadNotice: View {
    let stationID: String
    var end: Date? = nil
    let tz: TimeZone
    var gate: ChsCurrentGateInfo? = nil
    @ObservedObject private var downloads = ChsFitService.shared
    @ObservedObject private var net = Connectivity.shared

    var body: some View {
        let status = cardStatus(id: stationID)
        VStack(alignment: .center, spacing: 8) {
            Text("Additional data is required to improve accuracy")
            StationDownloadProgress(value: downloads.queue.job(stationID)?.downloadProgress ?? 0)
                .accessibilityValue(Text(status.label))
            if status == .offline || status == .notDownloaded {
                Text("More data will download when you reconnect")
            } else if status == .failed {
                Text("Additional download failed. Your downloaded predictions remain available.")
            } else if status == .retrying {
                CardStatusStrip(status: status)
            }
            if let end {
                Text("Predictions available through \(end.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: tz)))")
                    .foregroundStyle(SN.foam.opacity(0.7))
            }
            if let gate {
                Text(gate.provisionalHeadline)
                    .foregroundStyle(SN.amber)
            }
        }
        .font(.caption)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20).padding(.vertical, 8)
        .accessibilityIdentifier("chs-download-notice")
    }
}

/// "Falling 5.2 ft/hr" while the water moves faster than the ramp's first
/// anchor — the reason the line is yellow — else nil. `rate` is metres per
/// hour, signed; the height formatter converts it like a height.
func tideRateReading(rate: Double, imperial: Bool) -> String? {
    guard abs(rate) >= tideMovementRampAnchorsMHr[0] else { return nil }
    let value = formatHeight(abs(rate), imperial: imperial)
    let unit = heightUnit(imperial: imperial)
    return rate < 0
        ? String(localized: "Falling \(value) \(unit)/hr", comment: "Fast tide movement. Values are a formatted rate and compact height unit; '/hr' remains notation.")
        : String(localized: "Rising \(value) \(unit)/hr", comment: "Fast tide movement. Values are a formatted rate and compact height unit; '/hr' remains notation.")
}

/// The tide's next stop: its next high or low, or a fast run's fastest
/// point before it. A fast run is one stop, so once the selection reaches
/// its peak the turn is next.
func tideWaterStop(in timeline: TimelineData, after time: Date) -> CommentaryStop? {
    let drawn = timeline.drawnSpan
    let turn = firstCommentaryStop(timeline.tideExtremes, at: \.time, after: time, drawn: drawn).map {
        let high = $0.kind == .high
        return CommentaryStop(time: $0.time,
                              label: high
                                ? String(localized: "High", comment: "High-tide event label.")
                                : String(localized: "Low", comment: "Low-tide event label."),
                              spokenLabel: high
                                ? String(localized: "High tide", comment: "VoiceOver tide-event label.")
                                : String(localized: "Low tide", comment: "VoiceOver tide-event label."),
                              systemImage: high ? "arrow.up" : "arrow.down")
    }
    let peak = firstCommentaryStop(tideFlowArrows(timeline.tideRates), at: \.time, after: time, drawn: drawn)
    return [turn, peak.map(tideRatePeakStop)].compactMap { $0 }.min { $0.time < $1.time }
}

/// "Rising, 2.3 feet per hour": the rate as VoiceOver reads it, after the
/// state or the whole reading, since "ft/hr" is notation.
func spokenTideRate(after spoken: String, rate: Double, imperial: Bool) -> String {
    let value = formatHeight(abs(rate), imperial: imperial)
    let unit = spokenUnit(heightUnit(imperial: imperial))
    return String(localized: "\(spoken), \(value) \(unit) per hour", comment: "VoiceOver tide reading while the water moves fast. Values are the spoken state or reading, a formatted rate, and its spoken height unit.")
}

/// A fast run's fastest point as a commentary stop. Its rate is the lead's
/// to say; the pill names the moment.
func tideRatePeakStop(_ peak: TideRatePoint) -> CommentaryStop {
    peak.rate < 0
        ? CommentaryStop(time: peak.time,
                         label: String(localized: "Fastest fall", comment: "Tide event: the falling tide's fastest point."),
                         spokenLabel: String(localized: "Fastest falling tide", comment: "VoiceOver tide-event label."),
                         systemImage: "arrow.down.right")
        : CommentaryStop(time: peak.time,
                         label: String(localized: "Fastest rise", comment: "Tide event: the rising tide's fastest point."),
                         spokenLabel: String(localized: "Fastest rising tide", comment: "VoiceOver tide-event label."),
                         systemImage: "arrow.up.right")
}

#Preview {
    NavigationStack {
        TideDetailView(record: TideStationRecord.record(id: TideStationRecord.fridayHarborID)!)
    }
}
