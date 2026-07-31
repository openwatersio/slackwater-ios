// Slackwater — GPL v3. The paired tide pane on a gate's current detail
// (current-detail spec §2: current-led, tide as the paired reference track on
// the same time axis; web App.tsx "Tide at {companion.name}"). Data comes in
// from CurrentDetailView.recompute — the same engine calls the port's own
// TideDetailView makes — and the pane shares the gate's scrub time, so "slack
// at 16:02, and here's the tide height at that moment" reads in one gesture.
import SwiftUI
import Charts
import TideEngine

struct PairedTidePane: View {
    let port: TideStationRecord
    let dayPoints: [TidePoint]
    let extremes: [TideExtreme]  // widened ±1 day, for "next high/low"
    let effective: Date
    let imperial: Bool
    @Binding var preview: Date?
    @Binding var selected: Date

    private var tz: TimeZone { port.tz }
    private var unit: String { heightUnit(imperial: imperial) }
    private var dayExtremes: [TideExtreme] {
        guard let t0 = dayPoints.first?.time, let t1 = dayPoints.last?.time else { return [] }
        return extremes.filter { $0.time >= t0 && $0.time <= t1 }
    }
    private var nextExtreme: TideExtreme? { extremes.first { $0.time > effective } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    MonoLabel(text: "Tide at \(port.name)", size: 10, color: SN.steel, tracking: 1.4)
                    (Text(formatHeight(height(at: effective), imperial: imperial)).font(.fraunces(22))
                     + Text(" \(unit)").font(.geist(12)))
                        .foregroundStyle(SN.foam)
                }
                Spacer()
                if let next = nextExtreme {
                    VStack(alignment: .trailing, spacing: 1) {
                        MonoLabel(text: "Next \(next.kind == .high ? "High" : "Low")",
                                  size: 9, color: SN.foam.opacity(0.5), tracking: 1.4)
                        Text("\(formatHeight(next.height, imperial: imperial)) \(unit) · \(cardTime(next.time, tz))")
                            .font(.geist(12)).foregroundStyle(SN.leaf)
                    }
                }
            }
            chart
                .frame(height: 110)
                .padding(.top, 10)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(SN.cardFill)
        .overlay(alignment: .bottom) {
            Rectangle().fill(SN.steel.opacity(0.25)).frame(height: 0.5)
        }
    }

    private var chart: some View {
        let display: (Double) -> Double = { imperial ? toFeet($0) : $0 }
        let levels = dayPoints.map { display($0.height) }
        let minH = levels.min() ?? 0
        let maxH = levels.max() ?? 1
        let range = max(maxH - minH, 0.001)
        let t0 = dayPoints.first?.time ?? effective
        let t1 = dayPoints.last?.time ?? effective
        let clamped = min(max(effective, t0), t1)

        return Chart {
            ForEach(dayPoints, id: \.time) { p in
                AreaMark(x: .value("Time", p.time), y: .value("Height", display(p.height)))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(LinearGradient(
                        colors: [SN.steel.opacity(0.32), SN.sky.opacity(0.03)],
                        startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Time", p.time), y: .value("Height", display(p.height)))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .foregroundStyle(SN.sky.opacity(0.85))
            }
            ForEach(dayExtremes, id: \.time) { e in
                PointMark(x: .value("Time", e.time), y: .value("Height", display(e.height)))
                    .symbolSize(30)
                    .foregroundStyle(e.kind == .high ? SN.rising : SN.falling)
                    .annotation(position: e.kind == .high ? .top : .bottom, spacing: 4) {
                        Text(clockTime(e.time, tz))
                            .font(.geistMono(9)).foregroundStyle(SN.foam.opacity(0.5))
                    }
            }
            RuleMark(x: .value("Time", clamped))
                .lineStyle(StrokeStyle(lineWidth: 1))
                .foregroundStyle(SN.foam.opacity(0.35))
            PointMark(x: .value("Time", clamped), y: .value("Height", display(height(at: clamped))))
                .symbolSize(55)
                .foregroundStyle(.white)
        }
        .chartXScale(domain: t0...t1)
        .chartYScale(domain: (minH - 0.12 * range)...(maxH + 0.25 * range))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
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
                                selected = snapToNearest(min(max(raw, t0), t1),
                                                         times: dayExtremes.map(\.time))
                                preview = nil
                            })
            }
        }
    }

    private func time(at location: CGPoint, proxy: ChartProxy, geo: GeometryProxy) -> Date? {
        guard let plotFrame = proxy.plotFrame else { return nil }
        return proxy.value(atX: location.x - geo[plotFrame].origin.x)
    }

    /// Height at `t`, interpolated between the 10-min samples — the same
    /// crosshair read as the port's own detail (TideDetailView.interpolated).
    private func height(at t: Date) -> Double {
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
}
