// Slackwater — GPL v3. Current detail on the iOS scrub model (prototype
// TidesApp.dc.html): one continuous multi-day strip pans under a fixed
// centerline. A gate with a paired reference port renders BOTH tracks in the
// one strip — port tide above, gate current below, a separator between — with
// the port's readout above the strip and the gate's below (the prototype's
// combined-station anatomy). The old separate paired-tide pane collapsed into
// this: its "shared crosshair" is now the shared centerline time. No day
// pager; the schedule is a rolling multi-day list, rows scrub cross-day.
import SwiftUI
import TideEngine

struct CurrentDetailView: View {
    let record: CurrentStationRecord
    @AppStorage(unitsKey) private var units = "imperial"
    @AppStorage(speedUnitKey) private var speedUnit = "kn"
    @ObservedObject private var service = ChsFitService.shared

    @State private var live = appNow()
    @State private var scrubTime = appNow()
    @State private var timeline: TimelineData?
    @State private var showDownloads = false

    /// The gate identity behind a provisional fast answer — nil for a final
    /// model, which is what every readout below keys on.
    private var provisionalGate: ChsCurrentGateInfo? {
        service.isProvisional(record.id) ? record.chsGate : nil
    }
    /// Every number on this page is the fast answer's: amber, not white.
    private var readingColor: Color { provisionalGate == nil ? .white : SN.amber }

    private var pairedTide: TideStationRecord? { record.pairedTide }
    private var imperial: Bool { units == "imperial" }
    private var tz: TimeZone { record.tz }
    private var scrubSigned: Double { exactSigned(at: scrubTime) }
    private var phase: CurrentPhase { currentPhase(signed: scrubSigned) }
    private var nextSlack: CurrentEvent? {
        timeline?.currentEvents.first { $0.kind == .slack && $0.time > scrubTime }
    }
    /// The peak after the next slack — "then Max ebb 3.1 kn" (web `following`).
    private var following: CurrentEvent? {
        nextSlack.flatMap { slack in
            timeline?.currentEvents.first { $0.kind != .slack && $0.time > slack.time }
        }
    }
    private var dayOffset: Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal.dateComponents([.day], from: cal.startOfDay(for: live),
                                  to: cal.startOfDay(for: scrubTime)).day ?? 0
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                MapHeader(name: record.name, region: "\(record.region) · current",
                          latitude: record.latitude, longitude: record.longitude,
                          favoriteId: "current:" + record.id,
                          showReturn: abs(scrubTime.timeIntervalSince(live)) > 60,
                          onReturn: returnToNow)
                if let gate = provisionalGate {
                    ChsAmberCard(title: "Fast answer", headline: gate.provisionalHeadline,
                                 expectation: gate.provisionalExpectation,
                                 action: "See all downloads",
                                 identifier: "chs-provisional-warning") { showDownloads = true }
                }
                if let timeline {
                    scrubCard(timeline)
                    scheduleCard(timeline)
                }
                footer
            }
            .padding(.bottom, 42)
        }
        .ignoresSafeArea(edges: .top)
        .background(SN.page.ignoresSafeArea())
        .environment(\.timeZone, tz)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showDownloads) { OfflineManagerView() }
        .onAppear {
            if timeline == nil {
                timeline = TimelineData.build(tide: pairedTide, current: record, now: live)
            }
            RecentsStore.shared.record("current:" + record.id)
        }
        // The refinement lands under an open page: same station, new model. The
        // curve, the schedule and the amber marking all have to follow it.
        .onChange(of: record) { _, refined in
            timeline = TimelineData.build(tide: pairedTide, current: refined, now: live)
        }
    }

    // MARK: - Scrub card: tide-at-port readout, strip, current readout

    private var phaseColor: Color {
        switch phase {
        case .flood: SN.rising
        case .ebb: SN.falling
        case .slack: SN.foam.opacity(0.9)
        }
    }

    private func scrubCard(_ tl: TimelineData) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    MonoLabel(text: "\(relativeDayLabel(dayOffset, scrubTime, tz)) · \(dayLine(scrubTime, tz))", size: 11)
                    Text(cardTime(scrubTime, tz))
                        .font(.fraunces(30, .medium))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                }
                Spacer()
                let moon = SunMoon.moonIllumination(date: scrubTime)
                HStack(spacing: 8) {
                    MoonGlyph(fraction: moon.fraction, waxing: moon.waxing, size: 22)
                    Text(SunMoon.phaseName(phase: moon.phase))
                        .font(.geist(11))
                        .foregroundStyle(SN.foam.opacity(0.6))
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 88, alignment: .trailing)
                }
                .padding(.top, 2)
            }

            // Tide readout above the strip: the paired reference port's water
            // at the centerline time (absorbs the old PairedTidePane header).
            if let port = pairedTide {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        MonoLabel(text: "Tide at \(port.name)", size: 10, color: SN.steel, tracking: 1.4)
                        (Text(formatHeight(portHeight(port, at: scrubTime), imperial: imperial)).font(.fraunces(22))
                         + Text(" \(heightUnit(imperial: imperial))").font(.geist(12)))
                            .foregroundStyle(SN.foam)
                    }
                    Spacer()
                    if let next = tl.tideExtremes.first(where: { $0.time > scrubTime }) {
                        VStack(alignment: .trailing, spacing: 1) {
                            MonoLabel(text: "Next \(next.kind == .high ? "High" : "Low")",
                                      size: 9, color: SN.foam.opacity(0.5), tracking: 1.4)
                            Text("\(formatHeight(next.height, imperial: imperial)) \(heightUnit(imperial: imperial)) · \(cardTime(next.time, tz))")
                                .font(.geist(12)).foregroundStyle(SN.leaf)
                        }
                    }
                }
                .padding(.top, 14)
            }

            TimelineScrubStrip(data: tl, geo: TimelineGeo(data: tl),
                               imperial: imperial, speedUnit: speedUnit,
                               now: live, scrubTime: $scrubTime)
                .padding(.horizontal, -16)  // full-bleed strip
                .padding(.top, 12)

            // Current readout below the strip (prototype combined anatomy).
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    if phase == .slack {
                        Text("Slack").font(.fraunces(34)).foregroundStyle(readingColor)
                        Text("under \(formatSpeed(slackKn, unit: speedUnit)) \(speedUnitLabel(speedUnit))")
                            .font(.geist(13)).foregroundStyle(SN.foam.opacity(0.7))
                    } else {
                        // The tilde is the whole point of the provisional
                        // treatment: the number itself stops claiming to be
                        // exact, before any badge or card is read.
                        (Text(provisionalGate == nil ? "" : "~").font(.fraunces(34))
                         + Text(formatSpeed(abs(scrubSigned), unit: speedUnit)).font(.fraunces(34))
                         + Text(" \(speedUnitLabel(speedUnit))").font(.geist(14)))
                            .foregroundStyle(readingColor)
                        HStack(spacing: 4) {
                            Text(phaseWord(phase)).font(.geist(13))
                            CompassArrow(deg: record.setDegrees(signed: scrubSigned)).font(.geist(13))
                            Text(compass16(record.setDegrees(signed: scrubSigned))).font(.geist(13))
                        }
                        .foregroundStyle(provisionalGate == nil ? phaseColor : SN.amber.opacity(0.85))
                    }
                    if let gate = provisionalGate {
                        MonoLabel(text: "Fast answer · slack \(gate.provisionalTolerance)",
                                  size: 9, color: SN.amber, tracking: 1.2)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(SN.amber.opacity(0.16), in: Capsule())
                            .padding(.top, 2)
                            .accessibilityIdentifier("provisional-reading-badge")
                    }
                }
                Spacer()
                if let slack = nextSlack {
                    VStack(alignment: .trailing, spacing: 1) {
                        MonoLabel(text: "Next slack", size: 9, color: SN.foam.opacity(0.5), tracking: 1.4)
                        Text("\(provisionalGate == nil ? "" : "~")in \(countdown(from: scrubTime, to: slack.time)) · \(cardTime(slack.time, tz))")
                            .font(.geist(12)).foregroundStyle(provisionalGate == nil ? SN.leaf : SN.amber)
                        if let then = following {
                            Text("then \(then.turnLabel.lowercased()) \(formatSpeed(abs(then.speed), unit: speedUnit)) \(speedUnitLabel(speedUnit))")
                                .font(.geist(12)).foregroundStyle(SN.foam.opacity(0.7))
                        }
                    }
                }
            }
            .padding(.top, 8)

            MonoLabel(text: "‹ swipe to scrub · snaps to slack & peaks ›",
                      size: 9, color: SN.foam.opacity(0.4), tracking: 1.4)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(SN.cardFill)
        .overlay(alignment: .bottom) {
            Rectangle().fill(SN.leaf.opacity(0.22)).frame(height: 0.5)
        }
    }

    // MARK: - Rolling multi-day schedule (slack/max + port turns + sun)

    private func scheduleCard(_ tl: TimelineData) -> some View {
        MultiDaySchedule(entries: scheduleEntries(tl), tz: tz, today: tl.today,
                         scrubTime: scrubTime, onTap: { scrubTime = $0 })
            .background(SN.cardFill)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(SN.cardStroke, lineWidth: 0.5))
            .padding(.horizontal, 16)
    }

    private func scheduleEntries(_ tl: TimelineData) -> [ScheduleEntry] {
        let t0 = tl.today
        let t1 = t0.addingTimeInterval(Timeline.scheduleHours * 3600)
        var out: [ScheduleEntry] = tl.currentEvents
            .filter { $0.time >= t0 && $0.time <= t1 }
            .map { e in
                switch e.kind {
                case .slack:
                    ScheduleEntry(time: e.time, pill: .slack)
                case .maxFlood:
                    ScheduleEntry(time: e.time, pill: .flood,
                                  value: "\(formatSpeed(abs(e.speed), unit: speedUnit)) \(speedUnitLabel(speedUnit))",
                                  arrowDeg: record.floodDirection)
                case .maxEbb:
                    ScheduleEntry(time: e.time, pill: .ebb,
                                  value: "\(formatSpeed(abs(e.speed), unit: speedUnit)) \(speedUnitLabel(speedUnit))",
                                  arrowDeg: record.ebbDirection)
                }
            }
        out += tl.tideExtremes
            .filter { $0.time >= t0 && $0.time <= t1 }
            .map { ScheduleEntry(time: $0.time, pill: $0.kind == .high ? .high : .low,
                                 value: "\(formatHeight($0.height, imperial: imperial)) \(heightUnit(imperial: imperial))") }
        for day in tl.days {
            for (t, pill) in [(day.sunrise, SchedulePill.sunrise), (day.sunset, .sunset)] {
                if let t, t >= t0, t <= t1 { out.append(ScheduleEntry(time: t, pill: pill)) }
            }
        }
        return out.sorted { $0.time < $1.time }
    }

    private var footer: some View {
        VStack(spacing: 6) {
            MonoLabel(text: "Predictions — not for navigation",
                      size: 10, color: SN.foam.opacity(0.4), tracking: 1.4)
            if let gate = provisionalGate {
                Text("Flood sets \(Int(record.floodDirection.rounded()))°T · \(Int(ChsCurrentGateInfo.provisionalDays)) of \(Int(gate.fitDays)) days downloaded — still refining")
                    .font(.geist(11)).foregroundStyle(SN.amber.opacity(0.7))
                    .multilineTextAlignment(.center)
            } else if record.isChs {
                // Same register as the CHS tide footer (TideDetailView).
                Text("Flood sets \(Int(record.floodDirection.rounded()))°T · Downloaded from CHS (IWLS) — computed on this device, not CHS-published numbers")
                    .font(.geist(11)).foregroundStyle(SN.foam.opacity(0.3))
                    .multilineTextAlignment(.center)
            } else {
                Text("Flood sets \(Int(record.floodDirection.rounded()))°T · NOAA harmonic current prediction · \(speedUnit == "kn" ? "knots" : speedUnitLabel(speedUnit))")
                    .font(.geist(11)).foregroundStyle(SN.foam.opacity(0.3))
            }
            if let port = pairedTide {
                // Honesty line for the pairing (spec §2): the tide curve is the
                // reference port's water, not this gate's.
                Text("Tide shown is \(port.name) — the nearby reference port, not this station")
                    .font(.geist(11)).foregroundStyle(SN.foam.opacity(0.3))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    // MARK: - Data

    /// Engine-exact signed velocity — same call as the old committed readout.
    private func exactSigned(at t: Date) -> Double {
        record.engineStation.speeds(from: t, to: t.addingTimeInterval(1), step: 1).first?.speed ?? 0
    }

    /// Engine-exact port height — the same call the port's own detail makes.
    private func portHeight(_ port: TideStationRecord, at t: Date) -> Double {
        port.engineStation.heights(from: t, to: t.addingTimeInterval(1), step: 1).first?.height ?? 0
    }

    private func returnToNow() {
        live = appNow()
        scrubTime = live
    }
}
