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
    @State private var scrubTime = appNow()
    @State private var timeline: TimelineData?
    @State private var chsFittedAt: Date?
    /// The local midnight the window hangs from. Only `returnToNow` and (in
    /// Plan B) the range bar move it; everything else reads it.
    @State private var anchor = Date.distantPast

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
    /// The rate ramp's colour when the rate is out of the ordinary (#95: at
    /// Friday Harbor 0.8 ft/hr is nothing, at Ile Haute 8 ft/hr is the
    /// warning), else nil and the direction colour stands.
    private var rateWarningColor: Color? {
        guard let flow = timeline.flatMap({ timeline in
            tideFlowArrows(timeline.tideRates).first {
                abs($0.time.timeIntervalSince(scrubTime)) < 1
            }
        }), tideRateSeverity(flow.rate) != nil else { return nil }
        return SN.speedColour(Timeline.rampT(forTideRateMHr: abs(flow.rate)))
    }

    var body: some View {
        ScrubDetailScaffold(name: record.name, region: record.region,
                            favoriteId: record.id, tz: tz,
                            timeline: timeline, entries: scheduleEntries,
                            live: $live, scrubTime: $scrubTime,
                            onReturn: returnToNow,
                            anchor: $anchor,
                            onPicked: { _ in rebuild() },
                            scrubSummary: { _ in
                                guard let prev = prevExtreme, let next = nextExtreme else { return nil }
                                return ("Range", "\(formatHeight(abs(next.height - prev.height), imperial: imperial)) \(unit)")
                            },
                            above: {
                                readout
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 14)
                            },
                            card: { tl in
                                TimelineScrubStrip(data: tl, geo: TimelineGeo(data: tl),
                                                   imperial: imperial, now: live, scrubTime: $scrubTime,
                                                   onReturn: returnToNow)
                            },
                            links: { EmptyView() },
                            bottom: {
                                VStack(spacing: 14) {
                                    footer
                                    stationDetails
                                }
                            })
            .onAppear {
                if timeline == nil {
                    anchor = todayLocal(tz)
                    rebuild()
                }
                RecentsStore.shared.record(record.id)
                if record.isChs {
                    chsFittedAt = ChsModelStore.load(record.id)?.fittedAt
                }
            }
    }

    // MARK: - Readout between header and card: two tiles, now and next

    /// At a turn the water is at its high or low; otherwise it is on its way
    /// to one. Snap targets land exactly on the extreme, hence the 1 s.
    private var atTurn: TideExtreme? {
        timeline?.tideExtremes.first { abs($0.time.timeIntervalSince(scrubTime)) < 1 }
    }

    private func heightText(_ metres: Double) -> Text {
        Text(formatHeight(metres, imperial: imperial)).font(ReadoutType.hero.monospacedDigit())
            + Text(" \(unit)").font(ReadoutType.unit)
    }

    private var readout: some View {
        let trend = rising ? SN.rising : SN.falling
        let turn = atTurn
        return HStack(alignment: .top, spacing: 12) {
            // Now. The rate ramp's colour on the glyph when the rate is out of
            // the ordinary (#95), else the direction's.
            ReadoutTile(label: turn.map { $0.kind == .high ? "High" : "Low" } ?? (rising ? "Rising" : "Falling"),
                        caption: chartTime(scrubTime, tz),
                        accessibility: turn.map { $0.kind == .high ? "High tide" : "Low tide" } ?? (rising ? "Rising" : "Falling")) {
                Image(systemName: turn.map { $0.kind == .high ? "arrow.up.to.line" : "arrow.down.to.line" }
                                  ?? (rising ? "arrow.up.right" : "arrow.down.right"))
                    .foregroundStyle(rateWarningColor ?? trend)
            } value: {
                heightText(scrubHeight)
            }
            .accessibilityIdentifier("detail-reading")

            if let next = nextExtreme {
                // Relative from now; once scrubbed away, "in 4h" from an
                // arbitrary point means nothing, so the clock time.
                ReadoutTile(label: next.kind == .high ? "Next high" : "Next low",
                            caption: scrubbedAway(scrubTime, from: live) ? chartTime(next.time, tz)
                                : "in \(countdown(from: scrubTime, to: next.time))",
                            accessibility: next.kind == .high ? "Next high" : "Next low") {
                    Image(systemName: next.kind == .high ? "arrow.up.to.line" : "arrow.down.to.line")
                        .foregroundStyle(trend)
                } value: {
                    heightText(next.height)
                }
            }
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
                detailRow("Prediction", "\(record.constituents.count) harmonic constituents, computed on this device")
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
        scrubTime = live
        // The anchor too: return-to-now from a September window has to bring
        // the whole window back, not just park the centerline at a `now` that
        // isn't on this strip.
        anchor = todayLocal(tz)
        rebuild()
    }

    /// One place the timeline is rebuilt from, so the anchor and the record
    /// can never be applied by two different code paths.
    private func rebuild() {
        timeline = TimelineData.build(tide: record, current: nil, now: live, anchor: anchor)
    }
}

#Preview {
    NavigationStack {
        TideDetailView(record: TideStationRecord.all.first { $0.id == TideStationRecord.fridayHarborID }!)
    }
}
