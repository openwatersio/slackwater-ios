import SwiftUI

struct RangeOutlook: View {
    let timeline: TimelineData
    let selected: Date
    let at: Date
    private var tz: TimeZone { timeline.tz }

    static func peaks(_ timeline: TimelineData, at: Date) -> [Peak] {
        let tz = timeline.tz
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        let start = calendar.startOfDay(for: at)
        guard let end = calendar.date(byAdding: .day, value: 7, to: start) else { return [] }
        return SwingFigure.dailyPeaks(PeakStanding.swings(timeline.tideExtremes), tz: tz,
                                      window: (timeline.start, timeline.end))
            .filter { $0.time >= start && $0.time < end }
    }

    var body: some View {
        let peaks = Self.peaks(timeline, at: at)
        let biggest = max(peaks.map(\.magnitude).max() ?? 0, 0.001)
        GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(peaks, id: \.time) { peak in
                    let selected = dayLocal(peak.time, tz) == dayLocal(self.selected, tz)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(SN.graphLine.opacity(selected ? 1 : 0.4))
                        .frame(height: max(2, geometry.size.height * peak.magnitude / biggest))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
        .accessibilityHidden(true)
        .accessibilityIdentifier("range-outlook")
    }
}
