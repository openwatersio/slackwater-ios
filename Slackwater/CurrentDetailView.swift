// Slackwater — GPL v3. Current detail, variant 1b Modular — the currents twin
// of TideDetailView. State-first hero ("Ebbing 3.2 kn toward W"), signed
// velocity day curve (flood above the zero line, ebb below — web CurrentChart),
// slack / max flood / max ebb table, same scrub + day pager behavior.
import SwiftUI
import Charts
import TideEngine

private let day = 86_400.0

struct CurrentDetailView: View {
    let record: CurrentStationRecord

    @State private var live = Date.now
    @State private var selected = Date.now
    @State private var preview: Date?

    @State private var dayPoints: [CurrentPoint] = []
    @State private var dayEvents: [CurrentEvent] = []
    @State private var wideEvents: [CurrentEvent] = []
    @State private var committedSigned = 0.0

    private var tz: TimeZone { record.tz }
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal
    }
    private var effective: Date { preview ?? selected }
    private var effectiveSigned: Double {
        preview.map { interpolated(at: $0) } ?? committedSigned
    }
    private var phase: CurrentPhase { currentPhase(signed: effectiveSigned) }
    private var nextSlack: CurrentEvent? {
        wideEvents.first { $0.kind == .slack && $0.time > effective }
    }
    /// The peak after the next slack — "then Max ebb 3.1 kn" (web `following`).
    private var following: CurrentEvent? {
        nextSlack.flatMap { slack in wideEvents.first { $0.kind != .slack && $0.time > slack.time } }
    }
    private var dayOffset: Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: live),
                                to: calendar.startOfDay(for: selected)).day ?? 0
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                scrubCard
                scheduleCard
                footer
            }
            .padding(.bottom, 42)
        }
        .background(SN.page.ignoresSafeArea())
        .environment(\.timeZone, tz)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(SN.page, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(record.name).font(.fraunces(19, .semibold)).foregroundStyle(.white)
                    MonoLabel(text: "\(record.region) · current", size: 9,
                              color: SN.foam.opacity(0.8), tracking: 1.5)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if abs(selected.timeIntervalSince(live)) > 60 {
                    Button { returnToNow() } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .foregroundStyle(SN.leaf)
                    }
                }
            }
        }
        .onAppear { recompute() }
        .onChange(of: dayKey(selected)) { recompute() }
        .onChange(of: selected) { committedSigned = exactSigned(at: selected) }
    }

    // MARK: - Scrub card (state-first readout + signed curve)

    private var phaseColor: Color {
        switch phase {
        case .flood: SN.rising
        case .ebb: SN.falling
        case .slack: SN.foam.opacity(0.9)
        }
    }

    private var scrubCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    MonoLabel(text: "\(relativeDayLabel) · \(dayLine(effective, tz))", size: 11)
                    Text(cardTime(effective, tz))
                        .font(.fraunces(30, .medium))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                }
                Spacer()
            }

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    if phase == .slack {
                        Text("Slack").font(.fraunces(34)).foregroundStyle(.white)
                        Text("under \(formatSpeed(slackKn)) kn")
                            .font(.geist(13)).foregroundStyle(SN.foam.opacity(0.7))
                    } else {
                        (Text(formatSpeed(abs(effectiveSigned))).font(.fraunces(34))
                         + Text(" kn").font(.geist(14)))
                            .foregroundStyle(.white)
                        HStack(spacing: 4) {
                            Text(phaseWord(phase)).font(.geist(13))
                            CompassArrow(deg: record.setDegrees(signed: effectiveSigned)).font(.geist(13))
                            Text(compass16(record.setDegrees(signed: effectiveSigned))).font(.geist(13))
                        }
                        .foregroundStyle(phaseColor)
                    }
                }
                Spacer()
                if let slack = nextSlack {
                    VStack(alignment: .trailing, spacing: 1) {
                        MonoLabel(text: "Next slack", size: 9, color: SN.foam.opacity(0.5), tracking: 1.4)
                        Text("in \(countdown(from: effective, to: slack.time)) · \(cardTime(slack.time, tz))")
                            .font(.geist(12)).foregroundStyle(SN.leaf)
                        if let then = following {
                            Text("then \(then.turnLabel.lowercased()) \(formatSpeed(abs(then.speed))) kn")
                                .font(.geist(12)).foregroundStyle(SN.foam.opacity(0.7))
                        }
                    }
                }
            }
            .padding(.top, 14)

            chart
                .frame(height: 240)
                .padding(.top, 12)

            MonoLabel(text: "‹ drag to scrub · snaps to slack & peaks ›",
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

    private var chart: some View {
        let signed = dayPoints.map(\.speed)
        // Domain forced to bracket zero so the zero line always draws (web signedDomain).
        let minV = min(0, signed.min() ?? 0)
        let maxV = max(0, signed.max() ?? 1)
        let range = max(maxV - minV, 0.001)
        let t0 = dayPoints.first?.time ?? selected
        let t1 = dayPoints.last?.time ?? selected
        let effectiveClamped = min(max(effective, t0), t1)

        return Chart {
            // Flood lobe above zero, ebb lobe below — two clamped fills against
            // the zero baseline (web's one ribbon polygon, in Charts terms).
            ForEach(dayPoints, id: \.time) { p in
                AreaMark(x: .value("Time", p.time), yStart: .value("Zero", 0),
                         yEnd: .value("Flood", max(p.speed, 0)), series: .value("Lobe", "flood"))
                    .foregroundStyle(LinearGradient(
                        colors: [SN.rising.opacity(0.42), SN.rising.opacity(0.08)],
                        startPoint: .top, endPoint: .bottom))
                AreaMark(x: .value("Time", p.time), yStart: .value("Zero", 0),
                         yEnd: .value("Ebb", min(p.speed, 0)), series: .value("Lobe", "ebb"))
                    .foregroundStyle(LinearGradient(
                        colors: [SN.falling.opacity(0.08), SN.falling.opacity(0.42)],
                        startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Time", p.time), y: .value("Signed", p.speed))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .foregroundStyle(SN.sky)
            }
            // The zero line — the flood/ebb divide and the slack level, emphasized.
            RuleMark(y: .value("Slack", 0))
                .lineStyle(StrokeStyle(lineWidth: 1))
                .foregroundStyle(SN.foam.opacity(0.35))
            ForEach(dayEvents, id: \.time) { e in
                if e.kind == .slack {
                    PointMark(x: .value("Time", e.time), y: .value("Signed", 0))
                        .symbolSize(48)
                        .foregroundStyle(SN.foam.opacity(0.8))
                        .annotation(position: .bottom, spacing: 6) {
                            Text(clockTime(e.time, tz))
                                .font(.geistMono(10)).foregroundStyle(SN.foam.opacity(0.55))
                        }
                } else {
                    PointMark(x: .value("Time", e.time), y: .value("Signed", e.speed))
                        .symbolSize(48)
                        .foregroundStyle(e.kind == .maxFlood ? SN.rising : SN.falling)
                        .annotation(position: e.kind == .maxFlood ? .top : .bottom, spacing: 6) {
                            Text("\(formatSpeed(abs(e.speed))) kn")
                                .font(.geistMono(10)).foregroundStyle(SN.foam.opacity(0.55))
                        }
                }
            }
            RuleMark(x: .value("Time", effectiveClamped))
                .lineStyle(StrokeStyle(lineWidth: 1))
                .foregroundStyle(SN.foam.opacity(0.45))
                .annotation(position: .top, spacing: 2) {
                    Text(phase == .slack
                         ? "Slack · \(clockTime(effectiveClamped, tz))"
                         : "\(formatSpeed(abs(effectiveSigned))) kn · \(clockTime(effectiveClamped, tz))")
                        .font(.geistMono(11, .medium))
                        .foregroundStyle(SN.foam)
                }
            PointMark(x: .value("Time", effectiveClamped), y: .value("Signed", effectiveSigned))
                .symbolSize(90)
                .foregroundStyle(.white)
        }
        .chartXScale(domain: t0...t1)
        .chartYScale(domain: (minV - 0.14 * range)...(maxV + 0.22 * range))
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 4)) { value in
                AxisTick(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(SN.foam.opacity(0.2))
                AxisValueLabel {
                    if let d = value.as(Date.self) {
                        Text(String(clockTime(d, tz).prefix(2)))
                            .font(.geistMono(10)).foregroundStyle(SN.foam.opacity(0.4))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [minV, 0, maxV]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(SN.foam.opacity(0.12))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(String(format: "%.1f", v))
                            .font(.geistMono(10)).foregroundStyle(SN.foam.opacity(0.4))
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { g in
                                if let t = time(at: g.location, proxy: proxy, geo: geo) {
                                    preview = min(max(t, t0), t1)
                                }
                            }
                            .onEnded { g in
                                let raw = time(at: g.location, proxy: proxy, geo: geo) ?? effective
                                selected = snapToNearest(min(max(raw, t0), t1), times: dayEvents.map(\.time))
                                preview = nil
                            })
            }
        }
    }

    private func time(at location: CGPoint, proxy: ChartProxy, geo: GeometryProxy) -> Date? {
        guard let plotFrame = proxy.plotFrame else { return nil }
        let origin = geo[plotFrame].origin
        return proxy.value(atX: location.x - origin.x)
    }

    // MARK: - Schedule (day pager + slack/max table)

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(relativeDayLabel)
                        .font(.fraunces(22, .semibold)).foregroundStyle(SN.paper)
                    Text(dayLine(selected, tz))
                        .font(.geist(12)).foregroundStyle(SN.steel)
                }
                Spacer()
                HStack(spacing: 8) {
                    PagerButton(symbol: "chevron.left") { pageDay(-1) }
                    Button { returnToNow() } label: {
                        Text("Today")
                            .font(.geist(13, .medium))
                            .foregroundStyle(dayOffset == 0 ? SN.foam.opacity(0.35) : SN.foam)
                            .frame(height: 34)
                            .padding(.horizontal, 12)
                            .background(Color.white.opacity(0.06), in: Capsule())
                    }
                    .disabled(dayOffset == 0)
                    PagerButton(symbol: "chevron.right") { pageDay(1) }
                }
            }
            .padding(16)

            ForEach(dayEvents, id: \.time) { e in
                Divider().overlay(Color.white.opacity(0.08))
                Button { selected = e.time } label: {
                    HStack {
                        eventPill(e)
                        Text(clockTime(e.time, tz))
                            .font(.geistMono(15)).foregroundStyle(SN.foam)
                            .padding(.leading, 6)
                        Spacer()
                        if e.kind == .slack {
                            Text("—").font(.geist(15)).foregroundStyle(SN.foam.opacity(0.5))
                        } else {
                            (Text(formatSpeed(abs(e.speed))).font(.geist(15, .medium))
                             + Text(" kn").font(.geist(12)))
                                .foregroundStyle(SN.foam)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .opacity(e.time < effective ? 0.45 : 1)
                }
                .buttonStyle(.plain)
            }
            if dayEvents.isEmpty {
                Divider().overlay(Color.white.opacity(0.08))
                Text("Nothing on this day.")
                    .font(.geist(13)).foregroundStyle(SN.foam.opacity(0.5))
                    .padding(16)
            }
        }
        .background(SN.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(SN.cardStroke, lineWidth: 0.5))
        .padding(.horizontal, 16)
    }

    /// "● SLACK" on neutral, "↑ FLOOD"/"↑ EBB" with the set arrow on the
    /// phase color (web EventList pills, arrow at the station's flood/ebb set).
    private func eventPill(_ e: CurrentEvent) -> some View {
        Group {
            switch e.kind {
            case .slack:
                Text("● SLACK")
                    .foregroundStyle(SN.foam)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.white.opacity(0.12), in: Capsule())
            case .maxFlood:
                HStack(spacing: 3) {
                    CompassArrow(deg: record.floodDirection)
                    Text("FLOOD")
                }
                .foregroundStyle(SN.navyDeep)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(SN.rising, in: Capsule())
            case .maxEbb:
                HStack(spacing: 3) {
                    CompassArrow(deg: record.ebbDirection)
                    Text("EBB")
                }
                .foregroundStyle(SN.navyDeep)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(SN.falling, in: Capsule())
            }
        }
        .font(.geistMono(10, .medium))
        .tracking(0.5)
    }

    private var footer: some View {
        VStack(spacing: 6) {
            MonoLabel(text: "Predictions — not for navigation",
                      size: 10, color: SN.foam.opacity(0.4), tracking: 1.4)
            Text("Flood sets \(Int(record.floodDirection.rounded()))°T · NOAA harmonic current prediction · knots")
                .font(.geist(11)).foregroundStyle(SN.foam.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    // MARK: - Data

    private var relativeDayLabel: String {
        switch dayOffset {
        case 0: "Today"
        case 1: "Tomorrow"
        case -1: "Yesterday"
        default: weekdayName(selected, tz)
        }
    }

    private func dayKey(_ date: Date) -> Date { calendar.startOfDay(for: date) }

    private func recompute() {
        let start = calendar.startOfDay(for: selected)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let station = record.engineStation
        dayPoints = station.speeds(from: start, to: end, step: 600).filter { $0.time < end }
        // Widen then filter, so an event near local midnight isn't clipped.
        wideEvents = station.events(from: start.addingTimeInterval(-day),
                                    to: end.addingTimeInterval(day))
        dayEvents = wideEvents.filter { $0.time >= start && $0.time < end }
        committedSigned = exactSigned(at: selected)
    }

    private func exactSigned(at t: Date) -> Double {
        record.engineStation.speeds(from: t, to: t.addingTimeInterval(1), step: 1).first?.speed ?? 0
    }

    /// Signed velocity at `t`, linearly interpolated between bracketing samples —
    /// what the crosshair reads while dragging (web CurrentChart signedAt).
    private func interpolated(at t: Date) -> Double {
        guard let first = dayPoints.first else { return 0 }
        var prev = first
        for p in dayPoints {
            if t <= p.time {
                let span = p.time.timeIntervalSince(prev.time)
                let frac = span > 0 ? t.timeIntervalSince(prev.time) / span : 0
                return prev.speed + (p.speed - prev.speed) * frac
            }
            prev = p
        }
        return prev.speed
    }

    private func pageDay(_ delta: Int) {
        selected = selected.addingTimeInterval(Double(delta) * day)
    }

    private func returnToNow() {
        live = .now
        selected = live
    }
}
