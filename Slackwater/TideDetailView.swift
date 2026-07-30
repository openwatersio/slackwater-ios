// Slackwater — GPL v3. Tide detail, variant 1b Modular: uniform dark canvas,
// data-forward, the day curve as the hero with a scrubbable crosshair.
// Behavior mirrors slackwater-web: drag previews, release snaps to a turn
// within 30 minutes and commits; the schedule pages by day; rows scrub.
import SwiftUI
import Charts
import TideEngine

private let snapWindowMinutes = 30.0
private let hour = 3600.0
private let day = 86_400.0

struct TideDetailView: View {
    let record: TideStationRecord
    @AppStorage(unitsKey) private var units = "imperial"

    @State private var live = Date.now
    /// The committed instant everything reads (web's `now`): scrub release,
    /// row taps and day paging all move it.
    @State private var selected = Date.now
    /// Finger-down preview, distinct from `selected` until release (web useScrub).
    @State private var preview: Date?

    @State private var dayPoints: [TidePoint] = []
    @State private var dayExtremes: [TideExtreme] = []
    @State private var wideExtremes: [TideExtreme] = []
    @State private var committedHeight = 0.0

    private var imperial: Bool { units == "imperial" }
    private var tz: TimeZone { record.tz }
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal
    }
    private var effective: Date { preview ?? selected }
    private var effectiveHeight: Double {
        preview.map { interpolated(at: $0) } ?? committedHeight
    }
    private var nextExtreme: TideExtreme? { wideExtremes.first { $0.time > effective } }
    private var rising: Bool { nextExtreme.map { $0.kind == .high } ?? true }
    private var dayOffset: Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: live),
                                to: calendar.startOfDay(for: selected)).day ?? 0
    }
    private var unit: String { heightUnit(imperial: imperial) }

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
        .environment(\.timeZone, tz)  // chart axis strides in station-local hours
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(SN.page, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(record.name).font(.fraunces(19, .semibold)).foregroundStyle(.white)
                    MonoLabel(text: record.region, size: 9, color: SN.foam.opacity(0.8), tracking: 1.5)
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
        .onChange(of: selected) { committedHeight = exactHeight(at: selected) }
    }

    // MARK: - Scrub card (readout + chart)

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
                    (Text(formatHeight(effectiveHeight, imperial: imperial)).font(.fraunces(34))
                     + Text(" \(unit)").font(.geist(14)))
                        .foregroundStyle(.white)
                    HStack(spacing: 4) {
                        Text(rising ? "▲" : "▼").font(.geist(10))
                        Text(rising ? "Rising" : "Falling").font(.geist(13))
                    }
                    .foregroundStyle(rising ? SN.rising : SN.falling)
                }
                Spacer()
                if let next = nextExtreme {
                    VStack(alignment: .trailing, spacing: 1) {
                        MonoLabel(text: "Next \(next.kind == .high ? "High" : "Low")",
                                  size: 9, color: SN.foam.opacity(0.5), tracking: 1.4)
                        Text("\(formatHeight(next.height, imperial: imperial)) \(unit)")
                            .font(.fraunces(19)).foregroundStyle(SN.foam)
                        Text("in \(countdown(to: next.time)) · \(cardTime(next.time, tz))")
                            .font(.geist(12)).foregroundStyle(SN.leaf)
                    }
                }
            }
            .padding(.top, 14)

            chart
                .frame(height: 240)
                .padding(.top, 12)

            MonoLabel(text: "‹ drag to scrub · snaps to high & low ›",
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
        let display: (Double) -> Double = { self.imperial ? toFeet($0) : $0 }
        let levels = dayPoints.map { display($0.height) }
        let minH = levels.min() ?? 0
        let maxH = levels.max() ?? 1
        let range = max(maxH - minH, 0.001)
        let t0 = dayPoints.first?.time ?? selected
        let t1 = dayPoints.last?.time ?? selected
        let effectiveClamped = min(max(effective, t0), t1)

        return Chart {
            ForEach(dayPoints, id: \.time) { p in
                AreaMark(x: .value("Time", p.time), y: .value("Height", display(p.height)))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(LinearGradient(
                        colors: [SN.steel.opacity(0.38), SN.sky.opacity(0.04)],
                        startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Time", p.time), y: .value("Height", display(p.height)))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .foregroundStyle(SN.sky)
            }
            ForEach(dayExtremes, id: \.time) { e in
                PointMark(x: .value("Time", e.time), y: .value("Height", display(e.height)))
                    .symbolSize(48)
                    .foregroundStyle(e.kind == .high ? SN.rising : SN.falling)
                    .annotation(position: e.kind == .high ? .top : .bottom, spacing: 6) {
                        Text(clockTime(e.time, tz))
                            .font(.geistMono(10)).foregroundStyle(SN.foam.opacity(0.55))
                    }
            }
            RuleMark(x: .value("Time", effectiveClamped))
                .lineStyle(StrokeStyle(lineWidth: 1))
                .foregroundStyle(SN.foam.opacity(0.45))
                .annotation(position: .top, spacing: 2) {
                    Text("\(formatHeight(effectiveHeight, imperial: imperial)) \(unit) · \(clockTime(effectiveClamped, tz))")
                        .font(.geistMono(11, .medium))
                        .foregroundStyle(SN.foam)
                }
            PointMark(x: .value("Time", effectiveClamped),
                      y: .value("Height", display(effectiveHeight)))
                .symbolSize(90)
                .foregroundStyle(.white)
        }
        .chartXScale(domain: t0...t1)
        .chartYScale(domain: (minH - 0.12 * range)...(maxH + 0.22 * range))
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 4)) { value in
                AxisTick(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(SN.foam.opacity(0.2))
                AxisValueLabel {
                    if let d = value.as(Date.self) {
                        // 24h hour labels, like the web chart's "08"/"16".
                        Text(String(clockTime(d, tz).prefix(2)))
                            .font(.geistMono(10)).foregroundStyle(SN.foam.opacity(0.4))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [minH, (minH + maxH) / 2, maxH]) { value in
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
                                selected = snapToTurn(min(max(raw, t0), t1))
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

    // MARK: - Schedule (day pager + extremes table)

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
                    pagerButton("chevron.left") { pageDay(-1) }
                    Button { returnToNow() } label: {
                        Text("Today")
                            .font(.geist(13, .medium))
                            .foregroundStyle(dayOffset == 0 ? SN.foam.opacity(0.35) : SN.foam)
                            .frame(height: 34)
                            .padding(.horizontal, 12)
                            .background(Color.white.opacity(0.06), in: Capsule())
                    }
                    .disabled(dayOffset == 0)
                    pagerButton("chevron.right") { pageDay(1) }
                }
            }
            .padding(16)

            ForEach(dayExtremes, id: \.time) { e in
                Divider().overlay(Color.white.opacity(0.08))
                Button { selected = e.time } label: {
                    HStack {
                        Text(e.kind == .high ? "↑ HIGH" : "↓ LOW")
                            .font(.geistMono(10, .medium)).tracking(0.5)
                            .foregroundStyle(SN.navyDeep)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(e.kind == .high ? SN.rising : SN.falling, in: Capsule())
                        Text(clockTime(e.time, tz))
                            .font(.geistMono(15)).foregroundStyle(SN.foam)
                            .padding(.leading, 6)
                        Spacer()
                        (Text(formatHeight(e.height, imperial: imperial)).font(.geist(15, .medium))
                         + Text(" \(unit)").font(.geist(12)))
                            .foregroundStyle(SN.foam)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .opacity(e.time < effective ? 0.45 : 1)  // past rows dim, like the web
                }
                .buttonStyle(.plain)
            }
            if dayExtremes.isEmpty {
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

    private func pagerButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SN.foam)
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.06), in: Circle())
        }
    }

    private var footer: some View {
        VStack(spacing: 6) {
            MonoLabel(text: "Predictions — not for navigation",
                      size: 10, color: SN.foam.opacity(0.4), tracking: 1.4)
            Text("\(record.chartDatum) datum · NOAA harmonic prediction")
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
        // Chart domain is the station-local day (web filters its ±30h timeline
        // to the same day); drop the midnight-of-tomorrow sample.
        dayPoints = station.heights(from: start, to: end, step: 600).filter { $0.time < end }
        // Widen then filter, so a turn near local midnight isn't clipped (web predictRange).
        wideExtremes = station.extremes(from: start.addingTimeInterval(-day),
                                        to: end.addingTimeInterval(day))
        dayExtremes = wideExtremes.filter { $0.time >= start && $0.time < end }
        committedHeight = exactHeight(at: selected)
    }

    private func exactHeight(at t: Date) -> Double {
        record.engineStation.heights(from: t, to: t.addingTimeInterval(1), step: 1).first?.height ?? 0
    }

    /// Height at `t`, linearly interpolated between bracketing 10-min samples —
    /// what the web's crosshair reads while dragging (TideChart levelAt).
    private func interpolated(at t: Date) -> Double {
        guard let first = dayPoints.first else { return 0 }
        var prev = first
        for p in dayPoints {
            if t <= p.time {
                let span = p.time.timeIntervalSince(prev.time)
                let frac = span > 0 ? t.timeIntervalSince(prev.time) / span : 0
                return prev.height + (p.height - prev.height) * frac
            }
            prev = p
        }
        return prev.height
    }

    /// Released within 30 minutes of a turn, the line parks exactly on it (web snapToTurn).
    private func snapToTurn(_ t: Date) -> Date {
        var best: Date?
        var bestGap = snapWindowMinutes * 60
        for e in dayExtremes {
            let gap = abs(e.time.timeIntervalSince(t))
            if gap <= bestGap { bestGap = gap; best = e.time }
        }
        return best ?? t
    }

    private func pageDay(_ delta: Int) {
        selected = selected.addingTimeInterval(Double(delta) * day)
    }

    private func returnToNow() {
        live = .now
        selected = live
    }

    private func countdown(to target: Date) -> String {
        let minutes = max(Int(target.timeIntervalSince(effective) / 60), 0)
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
    }
}
