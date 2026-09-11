// Slackwater — GPL v3. Tide detail on the iOS scrub model (prototype
// TidesApp.dc.html, not the web's): a FIXED reading line at the center of the
// strip, the continuous multi-day curve panning underneath it. No day pager —
// free panning plus return-to-now. The schedule below is a
// rolling list over `Timeline.scheduleRange` — the week hanging off the
// anchor, and the strip is `Timeline.window` over the same anchor — with day
// headers; rows scrub, cross-day.
import SwiftUI
import TideEngine

struct TideDetailView: View {
    let record: TideStationRecord
    @AppStorage(unitsKey, store: AppGroup.defaults) private var units = "imperial"

    @State private var live = appNow()
    /// The single scrub time — whatever sits under the centerline.
    @State private var scrubTime = Timeline.introStart(for: appNow())
    /// Chunk cache + merged window + governed y-scale (TimelineChunks.swift).
    @State private var store: TimelineWindowStore?
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

    private var timeline: TimelineData? { store?.timeline }

    private var imperial: Bool { units == "imperial" }
    private var tz: TimeZone { record.tz }
    private var unit: String { heightUnit(imperial: imperial) }
    private var scrubHeight: Double { exactHeight(at: scrubTime) }
    private var nextExtreme: TideExtreme? {
        timeline?.tideExtremes.first { $0.time > scrubTime }
    }
    private var rising: Bool { nextExtreme.map { $0.kind == .high } ?? true }
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
    /// warning), else nil and the direction colour stands.
    private var rateWarningColor: Color? {
        fastTide ? SN.speedColour(Timeline.rampT(forTideRateMHr: abs(scrubRate))) : nil
    }
    /// The stop the pill names and its tap walks to: the next turn, or the
    /// sun's next rise or set when that comes first.
    private var nextStop: (time: Date, text: String)? {
        nextCommentaryStop(nextExtreme.map { (time: $0.time, text: $0.kind == .high ? "High" : "Low") },
                           sun: timeline?.days ?? [], after: scrubTime)
    }
    /// What the pill says: the rate while the tide is fast — it explains the
    /// yellow line under it — else the next stop.
    private var commentary: String? {
        if let fast = tideRateCommentary(rate: scrubRate, imperial: imperial) { return fast }
        return nextStop.map { commentaryText($0.text, at: $0.time, from: scrubTime, now: live) }
    }
    private var commentaryTint: Color? {
        fastTide ? SN.speedLabelColour(Timeline.rampT(forTideRateMHr: abs(scrubRate))) : nil
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
                            onPicked: { picked in store?.jump(to: scrubTime, anchor: picked) },
                            topBackdrop: AnyView(SkyBackdrop(sky: sky)),
                            above: { EmptyView() },
                            card: { tl in
                                let geo = TimelineGeo(data: tl, scale: store?.scale)
                                TimelineScrubStrip(data: tl, geo: geo,
                                                   imperial: imperial, now: live,
                                                   chromeInk: sky.ink,
                                                   scrubTime: $scrubTime,
                                                   onReturn: returnToNow,
                                                   commentary: commentary,
                                                   commentaryTint: commentaryTint,
                                                   onCommentary: scrubToCommentary,
                                                   scrollGate: store?.gate,
                                                   onViewportWidth: { viewportPts = $0 })
                                    .overlay(alignment: .top) { lead(ink: sky.ink) }
                            },
                            links: { tl, jump in
                                VStack(spacing: 12) {
                                    SummaryTiles(primary: range, moon: sky.illumination, at: scrubTime,
                                                 eclipse: tl.eclipses.first { $0.underway(at: scrubTime) },
                                                 onJump: jump,
                                                 latitude: record.latitude, longitude: record.longitude)
                                    if let nearby = nearbyCurrent {
                                        NearbyStationLink(item: nearby.item, km: nearby.km)
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
                    anchor = todayLocal(tz)
                    let s = TimelineWindowStore(source: .tide(record))
                    s.start(anchor: anchor, now: live)
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
            .onChange(of: scrubTime) { _, t in store?.focus(t, viewportPts: viewportPts) }
            // The schedule follows a scrub that has settled somewhere outside
            // its week — the strip is endless now, and a list still describing
            // three weeks ago would be a lie. A cancelled sleep is a scrub
            // still in motion, same rest rule as the chrome row's.
            .task(id: scrubTime) {
                guard (try? await Task.sleep(for: .milliseconds(600))) != nil else { return }
                if let tl = timeline, !tl.scheduleRange.contains(scrubTime) {
                    anchor = dayLocal(scrubTime, tz)
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
        return ("Range",
                "\(formatHeight(abs(next.height - prev.height), imperial: imperial)) \(unit)",
                prev.kind == .low ? "low to high" : "high to low")
    }

    private func lead(ink: Color) -> some View {
        let turn = atTurn
        let up = turn.map { $0.kind == .high } ?? rising
        let state = turn.map { $0.kind == .high ? "High" : "Low" } ?? (rising ? "Rising" : "Falling")
        return LeadCard(value: Text(formatHeight(scrubHeight, imperial: imperial)).font(ReadoutType.lead.monospacedDigit())
                            + Text(" \(unit)").font(ReadoutType.leadUnit),
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
                .foregroundStyle(rateWarningColor ?? (up ? SN.graphHigh : SN.graphLow))
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
        DetailFooter {
            if record.isChs {
                Text("\(record.chartDatum) datum · Downloaded from CHS (IWLS) — computed on this device, not CHS-published numbers")
                    .font(.caption2).foregroundStyle(SN.foam.opacity(0.3))
                    .multilineTextAlignment(.center)
            } else if let ref = record.referenceRecord {
                // A different accuracy class, and the reference can be far
                // away (Nurse Channel sits 600 km from Settlement Point).
                Text("\(record.chartDatum) datum · NOAA subordinate station: \(ref.name)'s tide, corrected by published offsets")
                    .font(.caption2).foregroundStyle(SN.foam.opacity(0.3))
                    .multilineTextAlignment(.center)
            } else if record.id.hasPrefix("noaa/") {
                Text("\(record.chartDatum) datum · NOAA harmonic prediction")
                    .font(.caption2).foregroundStyle(SN.foam.opacity(0.3))
            } else {
                Text("\(record.chartDatum) datum · TICON-4 harmonic prediction")
                    .font(.caption2).foregroundStyle(SN.foam.opacity(0.3))
            }
        }
    }

    private var stationDetails: some View {
        DisclosureGroup("Station details") {
            VStack(alignment: .leading, spacing: 10) {
                detailRow("Datum", record.detailsDatum)
                Text("Heights are measured above chart datum. A negative height means there is that much less water than the charted depth shows.")
                    .font(.caption)
                    .foregroundStyle(SN.foam.opacity(0.55))
                detailRow("Station", record.id)
                detailRow("Position", formatCoord(lat: record.latitude, lon: record.longitude))
                detailRow("Time zone", record.timezone)
                if let ref = record.referenceRecord {
                    detailRow("Reference", "\(ref.name), \(Int(distanceKm(record.latitude, record.longitude, ref.latitude, ref.longitude).rounded())) km away")
                    detailRow("Prediction", "Reference highs and lows, shifted and scaled by NOAA offsets, computed on this device")
                } else {
                    detailRow("Prediction", "\(record.constituents.count) harmonic constituents, computed on this device")
                }
                if let chsFittedAt {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Downloaded")
                        Spacer()
                        Text(chsFittedAt, style: .relative)
                    }
                    .font(.caption)
                }
            }
            .padding(.top, 8)
        }
        .font(.subheadline)
        .foregroundStyle(SN.foam.opacity(0.7))
        .tint(SN.foam.opacity(0.55))
        .padding(.horizontal, 24)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.caption)
    }

    // MARK: - Data

    /// Engine-exact height — the same call the old model's committed readout
    /// made, so the now-readout is unchanged by the scrub rework.
    private func exactHeight(at t: Date) -> Double {
        record.engineStation.heights(from: t, to: t.addingTimeInterval(1), step: 1).first?.height ?? 0
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
        scrubTime = live
    }
}

/// "Falling 5.2 ft/hr" while the water moves faster than the ramp's first
/// anchor — the reason the line is yellow — else nil. `rate` is metres per
/// hour, signed; the height formatter converts it like a height.
func tideRateCommentary(rate: Double, imperial: Bool) -> String? {
    guard abs(rate) >= tideMovementRampAnchorsMHr[0] else { return nil }
    return "\(rate < 0 ? "Falling" : "Rising") \(formatHeight(abs(rate), imperial: imperial)) \(heightUnit(imperial: imperial))/hr"
}

#Preview {
    NavigationStack {
        TideDetailView(record: TideStationRecord.all.first { $0.id == TideStationRecord.fridayHarborID }!)
    }
}
