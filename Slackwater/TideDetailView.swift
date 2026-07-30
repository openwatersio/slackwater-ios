// Slackwater — GPL v3. Today's tide curve + high/low extremes for one station.
import SwiftUI
import Charts
import TideEngine

private let toFeet = 3.28084  // engine heights are metres; web app displays feet

struct TideDetailView: View {
    let record: TideStationRecord

    // ponytail: computed inline on appear — no view model until a second consumer exists.
    @State private var points: [TidePoint] = []
    @State private var extremes: [TideExtreme] = []

    private var tz: TimeZone { TimeZone(identifier: record.timezone) ?? .current }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Today · \(record.chartDatum) · feet")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Chart {
                    ForEach(points, id: \.time) { p in
                        LineMark(x: .value("Time", p.time), y: .value("Height", p.height * toFeet))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(.cyan)
                    }
                    ForEach(extremes, id: \.time) { e in
                        PointMark(x: .value("Time", e.time), y: .value("Height", e.height * toFeet))
                            .foregroundStyle(.white)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 6)) {
                        AxisGridLine(); AxisTick()
                        AxisValueLabel(format: .dateTime.hour().locale(.current), centered: false)
                    }
                }
                .frame(height: 260)

                ForEach(extremes, id: \.time) { e in
                    HStack {
                        Text(e.kind == .high ? "High" : "Low")
                            .fontWeight(.semibold)
                            .foregroundStyle(e.kind == .high ? .cyan : .orange)
                        Text(e.time, format: .dateTime.hour().minute())
                        Spacer()
                        Text(String(format: "%.1f ft", e.height * toFeet))
                            .monospacedDigit()
                    }
                }

                Text("Predictions — not for navigation")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 8)
            }
            .padding()
        }
        .background(navy)
        .navigationTitle(record.name)
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.timeZone, tz)
        .onAppear(perform: compute)
    }

    private func compute() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let start = cal.startOfDay(for: .now)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        let station = record.engineStation
        points = station.heights(from: start, to: end, step: 600)
        extremes = station.extremes(from: start, to: end)
    }
}
