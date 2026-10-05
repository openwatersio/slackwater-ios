// Slackwater — GPL v3. Tide detail: a continuous strip beneath a fixed
// centerline and a rolling schedule anchored to the selected local week.
// Product contract: docs/scrubber.md.
import SwiftUI
import SlackwaterKit

struct TideDetailView: View {
    let record: TideStationRecord
    var preview: ChsTidePreview? = nil
    @AppStorage(unitsKey, store: AppGroup.defaults) private var units = "imperial"

    @State private var live = appNow()
    /// The single scrub time — whatever sits under the centerline.
    @State private var scrubTime = Timeline.introStart(for: appNow())
    /// Chunk cache + merged window + governed y-scale (TimelineChunks.swift).
    @State private var store: TimelineWindowStore?
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
    /// The line is on the ramp here: the water is moving faster than the
    /// first anchor, the same test `tideRateStops` colours by.
    private var fastTide: Bool { abs(scrubRate) >= tideMovementRampAnchorsMHr[0] }
    /// The rate ramp's colour when the rate is out of the ordinary (#95: at
    /// Friday Harbor 0.8 ft/hr is nothing, at Ile Haute 8 ft/hr is the
    /// warning), else nil and the direction colour stands. The lead's glyph
    /// and the pill under it wear the one ink, lifted for the sky both float
    /// on — the ramp's red end is unreadable against a sunrise otherwise.
    private func rateWarning(over ground: UInt32) -> Color? {
        fastTide ? SN.speedLabelColour(Timeline.rampT(forTideRateMHr: abs(scrubRate)), over: ground) : nil
    }
    /// The stop the pill names and its tap walks to: the next turn, or the
    /// sun's next rise or set when that comes first.
    private var nextStop: CommentaryStop? {
        nextCommentaryStop(nextExtreme.map {
            let high = $0.kind == .high
            return CommentaryStop(time: $0.time,
                                  label: high
                                    ? String(localized: "High", comment: "High-tide event label.")
                                    : String(localized: "Low", comment: "Low-tide event label."),
                                  spokenLabel: high
                                    ? String(localized: "High tide", comment: "VoiceOver tide-event label.")
                                    : String(localized: "Low tide", comment: "VoiceOver tide-event label."),
                                  systemImage: high ? "arrow.up" : "arrow.down")
        },
                           sun: timeline?.days ?? [], after: scrubTime)
    }
    /// What the pill says: the rate while the tide is fast — it explains the
    /// yellow line under it — else the next stop.
    private var commentary: CommentaryContent? {
        if let fast = tideRateCommentary(rate: scrubRate, imperial: imperial) {
            return CommentaryContent(label: fast, accessibilityLabel: fast)
        }
        return nextStop.map { commentaryContent($0, from: scrubTime) }
    }
    /// A fast tide's tap goes to this run's fastest point — the flow arrow the
    /// magnet already snaps to — so the pill then reads the peak rate. From
    /// the peak itself, or a quiet tide, it goes to the next stop.
    private func scrubToCommentary() {
        if fastTide, let tl = timeline,
           let peak = tideFlowArrows(tl.tideRates)
               .filter({ ($0.rate < 0) == (scrubRate < 0) })
               .min(by: { abs($0.time.timeIntervalSince(scrubTime)) < abs($1.time.timeIntervalSince(scrubTime)) }),
           abs(peak.time.timeIntervalSince(scrubTime)) > 1 {
            scrubTime = peak.time
        } else if let next = nextStop {
            scrubTime = next.time
        }
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
                                    scrubTime = min(max(scrubTime, coverage.lowerBound), coverage.upperBound)
                                } else { store?.jump(to: scrubTime, anchor: picked) }
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
                                                   commentaryTint: rateWarning(over: sky.chromeGround),
                                                   onCommentary: scrubToCommentary,
                                                   scrollGate: store?.gate ?? previewGate,
                                                   onViewportWidth: { viewportPts = $0 })
                                    .overlay(alignment: .top) { lead(sky: sky) }
                            },
                            links: { tl, jump in
                                VStack(spacing: 12) {
                                    if let coverage = activePreview?.coverage {
                                        TidePreviewNotice(stationID: record.id, end: coverage.upperBound, tz: tz)
                                    }
                                    SummaryTiles(primary: range,
                                                 primaryDetail: rangeDetail,
                                                 // A year, which is what the tile is
                                                 // flagging: this water follows one.
                                                 primarySymbol: record.seasonalRatio == nil ? nil : "calendar",
                                                 moon: sky.illumination, at: scrubTime,
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
                if preview == nil, store == nil {
                    let s = TimelineWindowStore(source: .tide(record))
                    s.start(anchor: anchor, now: live, focus: linked ? scrubTime : nil)
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
                    scrubTime = min(max(scrubTime, coverage.lowerBound), coverage.upperBound)
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
            }
            .onChange(of: scrubTime) { _, t in
                if let coverage = activePreview?.coverage {
                    let clamped = min(max(t, coverage.lowerBound), coverage.upperBound)
                    if t != clamped { scrubTime = clamped }
                } else { store?.focus(t, viewportPts: viewportPts) }
            }
            // The schedule follows a scrub that has settled somewhere outside
            // its window — the strip is endless now, and a list still describing
            // three weeks ago would be a lie. A cancelled sleep is a scrub
            // still in motion, same rest rule as the chrome row's.
            .task(id: scrubTime) {
                guard activePreview == nil else { return }
                guard (try? await Task.sleep(for: .milliseconds(600))) != nil else { return }
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
                // At a seasonal station the caption gives up the direction for
                // the reason the number is small. The direction is the lesser
                // fact — the curve and the schedule both show it — and a tile
                // caption is one line, so the two cannot both be here.
                record.seasonalRatio.map(seasonalCaption) ?? rangeDirection)
    }

    /// Which way this swing runs, when there is nothing more pressing to say.
    private var rangeDirection: String {
        prevExtreme?.kind == .low
            ? String(localized: "low to high", comment: "Tide-range direction.")
            : String(localized: "high to low", comment: "Tide-range direction.")
    }

    /// The Range tile's sheet, and the marker on the tile that says it is there.
    /// Both appear only where the water is seasonal rather than tidal.
    private var rangeDetail: (() -> AnyView)? {
        guard let ratio = record.seasonalRatio, let range else { return nil }
        let place = record.name
        return { AnyView(RangeDetailSheet(value: range.value, direction: self.rangeDirection,
                                          seasonalRatio: ratio, place: place)) }
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
        String(localized: "\(leadState) \(formatHeight(scrubHeight, imperial: imperial)) \(spokenUnit(unit))", comment: "VoiceOver tide reading. Values are tide state, formatted height, and spoken unit.")
    }

    private func lead(sky: SkyState) -> some View {
        let ink = sky.ink
        let turn = atTurn
        let up = turn.map { $0.kind == .high } ?? rising
        let state = leadState
        return LeadCard(value: formatHeight(scrubHeight, imperial: imperial),
                        unit: unit,
                        time: leadWhen(scrubTime, tz),
                        valueColor: ink,
                        timeColor: ink) {
            // Word then glyph, the order the current lead reads in.
            Text(state).fontWeight(.medium).foregroundStyle(ink.opacity(0.85))
            // The graph's own two inks, so the eyebrow names the curve the
            // reader is looking at — unless the rate is out of the ordinary
            // (#95), which outranks direction.
            Image(systemName: turn.map { $0.kind == .high ? "arrow.up.to.line" : "arrow.down.to.line" }
                              ?? (rising ? "arrow.up.right" : "arrow.down.right"))
                .foregroundStyle(rateWarning(over: sky.chromeGround) ?? (up ? SN.graphHigh : SN.graphLow))
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
            } else {
                Text("\(record.chartDatum) chart datum. TICON-4 harmonic prediction.")
                    .font(.caption2).foregroundStyle(SN.foam.opacity(0.3))
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

    private func returnToNow() {
        live = appNow()
        // The anchor too: return-to-now from a September window has to bring
        // the whole schedule week back, not just park the centerline. The
        // strip itself rides home animated within `Timeline.snapJumpHours`
        // and lands unanimated past it — the scrubber decides by distance;
        // the store only guarantees now's chunks exist.
        anchor = todayLocal(tz)
        store?.jump(to: live, anchor: anchor)
        if let coverage = activePreview?.coverage {
            scrubTime = min(max(live, coverage.lowerBound), coverage.upperBound)
        } else { scrubTime = live }
    }
}

private struct TidePreviewNotice: View {
    let stationID: String
    let end: Date
    let tz: TimeZone
    @ObservedObject private var downloads = ChsFitService.shared
    @ObservedObject private var net = Connectivity.shared

    var body: some View {
        VStack(alignment: .center, spacing: 4) {
            Text("Predictions available through \(end.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: tz)))")
            Text(tidePreviewDownloadStatus(downloads.queue.job(stationID), online: net.online))
                .foregroundStyle(SN.foam.opacity(0.7))
        }
        .font(.caption)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20).padding(.vertical, 8)
        .accessibilityIdentifier("chs-tide-preview")
    }
}

/// "Falling 5.2 ft/hr" while the water moves faster than the ramp's first
/// anchor — the reason the line is yellow — else nil. `rate` is metres per
/// hour, signed; the height formatter converts it like a height.
func tideRateCommentary(rate: Double, imperial: Bool) -> String? {
    guard abs(rate) >= tideMovementRampAnchorsMHr[0] else { return nil }
    let value = formatHeight(abs(rate), imperial: imperial)
    let unit = heightUnit(imperial: imperial)
    return rate < 0
        ? String(localized: "Falling \(value) \(unit)/hr", comment: "Fast tide movement. Values are a formatted rate and compact height unit; '/hr' remains notation.")
        : String(localized: "Rising \(value) \(unit)/hr", comment: "Fast tide movement. Values are a formatted rate and compact height unit; '/hr' remains notation.")
}

#Preview {
    NavigationStack {
        TideDetailView(record: TideStationRecord.record(id: TideStationRecord.fridayHarborID)!)
    }
}
