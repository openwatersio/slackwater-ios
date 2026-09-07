// Slackwater — GPL v3. Current detail on the iOS scrub model (prototype
// TidesApp.dc.html): one continuous multi-day strip pans under a fixed
// centerline, current only — a paired reference port's tide no longer rides
// the same track (split-scrubbers spec §1). The port stays reachable one tap
// away via TideAtPortLink, in the scrub card. No day pager; the schedule is a
// rolling multi-day list, rows scrub cross-day.
import SwiftUI
import TideEngine

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

struct CurrentDetailView: View {
    let record: CurrentStationRecord
    @AppStorage(speedUnitKey, store: AppGroup.defaults) private var speedUnit = "kn"
    @AppStorage(AppGroup.slackWindowSpeedKey, store: AppGroup.defaults)
    private var slackWindowSpeed = defaultSlackThresholdKn
    @ObservedObject private var service = ChsFitService.shared
    @ObservedObject private var net = Connectivity.shared

    @State private var live = appNow()
    @State private var scrubTime = Timeline.introStart(for: appNow())
    @State private var timeline: TimelineData?
    /// The local midnight the window hangs from. Only `returnToNow` and (in
    /// Plan B) the range bar move it; everything else reads it.
    @State private var anchor = Date.distantPast
    @State private var showDownloads = false
    // Re-forwarded onto the sheet below — `.sheet` content doesn't inherit a
    // custom `@Environment` key set above the presenting view on its own
    // (SlackwaterApp.swift's `.sheet(showDownloads)` comment has the story).
    @Environment(\.openChsRoute) private var openChsRoute

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
        CurrentLead(timeline: tl, scrubTime: scrubTime, now: live, signed: exactSigned(at: scrubTime),
                    floodDeg: record.floodDirection, ebbDeg: record.ebbDirection,
                    speedUnit: speedUnit, tz: tz, ink: ink, provisional: provisionalGate != nil)
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
                            onPicked: { _ in rebuild() },
                            topBackdrop: AnyView(SkyBackdrop(sky: sky)),
                            above: {
                                if let gate = provisionalGate {
                                    ChsAmberCard(title: "Fast answer", headline: gate.provisionalHeadline,
                                                 expectation: gate.provisionalExpectation(online: net.online),
                                                 action: "See all downloads",
                                                 identifier: "chs-provisional-warning") { showDownloads = true }
                                        .padding(.bottom, 14)
                                }
                            },
                            card: { tl in
                                // No badge over the strip: the amber card
                                // above, the amber numbers and the tilde
                                // already say the reading is provisional, and
                                // a fourth marking landed in the pill row.
                                CurrentScrubCard(lead: lead(tl, ink: sky.ink), data: tl,
                                                 speedUnit: speedUnit, now: live,
                                                 floodDeg: record.floodDirection, ebbDeg: record.ebbDirection,
                                                 sky: sky,
                                                 scrubTime: $scrubTime, onReturn: returnToNow)
                            },
                            links: { tl, jump in
                                VStack(spacing: 12) {
                                    SummaryTiles(primary: lead(tl).nextMax, moon: sky.illumination,
                                                 at: scrubTime,
                                                 eclipse: tl.eclipses.first { $0.underway(at: scrubTime) },
                                                 onJump: jump,
                                                 latitude: record.latitude, longitude: record.longitude)
                                    if let port = pairedTide { TideAtPortLink(port: port) }
                                }
                            },
                            bottom: { footer })
            .sheet(isPresented: $showDownloads) { OfflineManagerView().environment(\.openChsRoute, openChsRoute) }
            .onAppear {
                if timeline == nil {
                    anchor = todayLocal(tz)
                    rebuild()
                }
                RecentsStore.shared.record(record.itemId)
            }
            // The refinement lands under an open page: same station, new model. The
            // curve, the schedule and the amber marking all have to follow it.
            .onChange(of: record) { _, _ in rebuild() }
            .onChange(of: slackWindowSpeed) { _, _ in rebuild() }
    }

    // MARK: - Colour

    /// Kept as the tests' named binding (ColourAndFormTests); the palette
    /// itself lives in `StationGlyph.colour(for:)`. Slack is the app's "go"
    /// colour — the moment the app is named for, the same on every surface.
    static func phaseColor(_ phase: CurrentPhase) -> Color {
        StationGlyph.colour(for: phase == .flood ? .flood : phase == .ebb ? .ebb : .slack)
    }

    private var footer: some View {
        DetailFooter {
            if let gate = provisionalGate {
                Text("Flood sets \(Int(record.floodDirection.rounded()))°T · \(Int(ChsCurrentGateInfo.provisionalDays)) of \(Int(gate.fitDays)) days downloaded — still refining")
                    .font(.caption2).foregroundStyle(SN.amber.opacity(0.7))
                    .multilineTextAlignment(.center)
            } else if record.isChs {
                // Same register as the CHS tide footer (TideDetailView).
                Text("Flood sets \(Int(record.floodDirection.rounded()))°T · Downloaded from CHS (IWLS) — computed on this device, not CHS-published numbers")
                    .font(.caption2).foregroundStyle(SN.foam.opacity(0.3))
                    .multilineTextAlignment(.center)
            } else if let ref = record.referenceRecord {
                // A different accuracy class: NOAA's table offsets against the
                // reference's events, with a drawn curve between them.
                Text("Flood sets \(Int(record.floodDirection.rounded()))°T · NOAA subordinate station: \(ref.name)'s slacks and maxima, corrected by published offsets")
                    .font(.caption2).foregroundStyle(SN.foam.opacity(0.3))
                    .multilineTextAlignment(.center)
            } else {
                Text("Flood sets \(Int(record.floodDirection.rounded()))°T · NOAA harmonic current prediction · \(speedUnit == "kn" ? "knots" : speedUnitLabel(speedUnit))")
                    .font(.caption2).foregroundStyle(SN.foam.opacity(0.3))
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
        timeline = TimelineData.build(tide: nil, current: record, now: live, anchor: anchor,
                                      threshold: normalizedSlackThresholdKn(slackWindowSpeed))
    }
}

#Preview {
    NavigationStack {
        CurrentDetailView(record: CurrentStationRecord.all.first { $0.name == "Deception Pass (Narrows)" }!)
    }
}
