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
    /// Chunk cache + merged window + governed y-scale (TimelineChunks.swift).
    @State private var store: TimelineWindowStore?
    /// The local midnight the schedule week hangs from. `returnToNow`, the
    /// picker, and the settle-follow below move it.
    @State private var anchor = Date.distantPast
    @State private var viewportPts: CGFloat = 0
    @State private var showDownloads = false
    /// The nearest tide-series station inside `nearbyStationRadiusKm` — the
    /// discovery fallback when no curated `tideReference` pairs this station.
    /// Computed once on appear; the body re-evaluates on every scrub tick.
    @State private var nearbyTide: (item: StationItem, km: Double)?
    // Re-forwarded onto the sheet below — `.sheet` content doesn't inherit a
    // custom `@Environment` key set above the presenting view on its own
    // (SlackwaterApp.swift's `.sheet(showDownloads)` comment has the story).
    @Environment(\.openChsRoute) private var openChsRoute

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
                            onPicked: { picked in store?.jump(to: scrubTime, anchor: picked) },
                            topBackdrop: AnyView(SkyBackdrop(sky: sky)),
                            alertOffer: currentAlertOffer(
                                // CurrentLead's `atMax`, read here because the lead keeps it private.
                                maxIsFlood: timeline?.currentEvents.first {
                                    $0.kind != .slack && abs($0.time.timeIntervalSince(scrubTime)) < 1
                                }.map { $0.kind == .maxFlood },
                                onEclipseContact: isOnEclipseContact(scrubTime, timeline?.eclipses ?? [])),
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
                                                 scrubTime: $scrubTime, onReturn: returnToNow,
                                                 scale: store?.scale,
                                                 scrollGate: store?.gate,
                                                 onViewportWidth: { viewportPts = $0 })
                            },
                            links: { tl, jump in
                                VStack(spacing: 12) {
                                    SummaryTiles(primary: lead(tl).nextMax, moon: sky.illumination,
                                                 at: scrubTime,
                                                 eclipse: tl.eclipses.first { $0.underway(at: scrubTime) },
                                                 onJump: jump,
                                                 latitude: record.latitude, longitude: record.longitude)
                                    if let port = pairedTide {
                                        TideAtPortLink(port: port)
                                    } else if let nearby = nearbyTide {
                                        NearbyStationLink(item: nearby.item, km: nearby.km)
                                    }
                                }
                            },
                            bottom: { footer })
            .sheet(isPresented: $showDownloads) { OfflineManagerView().environment(\.openChsRoute, openChsRoute) }
            .onAppear {
                if store == nil {
                    anchor = todayLocal(tz)
                    resetStore(focus: nil)
                }
                RecentsStore.shared.record(record.itemId)
                if pairedTide == nil, nearbyTide == nil,
                   let n = StationItem.nearest(.tide, toLat: record.latitude, lon: record.longitude),
                   n.km <= nearbyStationRadiusKm {
                    nearbyTide = n
                }
            }
            .onChange(of: scrubTime) { _, t in store?.focus(t, viewportPts: viewportPts) }
            // The schedule follows a scrub that has settled outside its week —
            // the strip is endless now. A cancelled sleep is a scrub still in
            // motion, same rest rule as the chrome row's.
            .task(id: scrubTime) {
                guard (try? await Task.sleep(for: .milliseconds(600))) != nil else { return }
                if let tl = timeline, !tl.scheduleRange.contains(scrubTime) {
                    anchor = dayLocal(scrubTime, tz)
                    store?.setAnchor(anchor)
                }
            }
            // The refinement lands under an open page: same station, new model. The
            // curve, the schedule and the amber marking all have to follow it —
            // a fresh store, parked where the scrub already is.
            .onChange(of: record) { _, _ in resetStore(focus: scrubTime) }
            .onChange(of: slackWindowSpeed) { _, _ in resetStore(focus: scrubTime) }
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
        // The anchor too: return-to-now from a September window has to bring
        // the whole schedule week back. The scrubber rides home animated
        // within `Timeline.snapJumpHours` and lands unanimated past it.
        anchor = todayLocal(tz)
        store?.jump(to: live, anchor: anchor)
        scrubTime = live
    }

    /// One place the store is created from, so the record and the slack
    /// threshold can never be applied by two different code paths. `focus`
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
