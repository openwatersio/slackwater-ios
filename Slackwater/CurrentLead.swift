// Slackwater — GPL v3. The current track's lead and commentary, one anatomy
// for every station with real velocities, harmonic or CHS-published: the
// speed as the hero, the set arrow and phase word above it, the time below,
// and the next significant stop the commentary pill walks to.
import SwiftUI
import TideEngine

struct CurrentLead: View {
    let timeline: TimelineData
    let scrubTime: Date
    let now: Date
    /// The velocity under the centerline — engine-exact for a harmonic
    /// station, the fetched series for a gate.
    let signed: Double
    let floodDeg: Double
    let ebbDeg: Double
    let speedUnit: String
    let tz: TimeZone
    var ink: Color = .white
    /// A fast answer marks every number with a tilde and paints them amber.
    var provisional = false

    private var phase: CurrentPhase { currentPhase(signed: signed) }
    private var isSlack: Bool { timeline.containingSlackWindow(at: scrubTime) != nil || phase == .slack }
    private var tilde: String { provisional ? "~" : "" }
    private var setDegrees: Double { signed >= 0 ? floodDeg : ebbDeg }
    private var readingColor: Color { provisional ? SN.amber : ink }

    /// The stops the commentary walks: a window opening, its closing (the
    /// run that begins), each max, and a bare slack where no window exists.
    /// Strictly after the scrub, so landing on one advances to the next.
    var nextSignificant: (time: Date, text: String)? {
        var stops: [(time: Date, text: String)] = []
        // The windows' own slacks, gathered once: the event loop below asks
        // this of every slack event, and the linear scan it replaces made
        // that quadratic across a week of events.
        var windowSlacks = Set<Date>()
        let seriesEnd = timeline.currentPoints.last?.time ?? .distantPast
        for w in timeline.slackWindows {
            stops.append((w.start, "Slack"))
            // A window that runs to the series' end never closes, so no run
            // begins there. Direction is read a second past the edge.
            if w.end < seriesEnd {
                let v = timeline.velocityAt(w.end.addingTimeInterval(1))
                stops.append((w.end, v >= 0 ? "Flood" : "Ebb"))
            }
            windowSlacks.insert(w.slack)
        }
        for e in timeline.currentEvents {
            switch e.kind {
            case .slack:
                if !windowSlacks.contains(e.time) { stops.append((e.time, "Slack")) }
            case .maxFlood, .maxEbb:
                stops.append((e.time, e.kind == .maxFlood ? "Max flood" : "Max ebb"))
            }
        }
        return stops.filter { $0.time > scrubTime.addingTimeInterval(1) }.min { $0.time < $1.time }
    }

    var commentary: String? {
        nextSignificant.map { commentaryText("\(tilde)\($0.text)", at: $0.time, from: scrubTime, now: now) }
    }

    /// The summary tile's number: the maximum the water is heading for. A
    /// current's swing is the peak ahead, not a peak-to-peak span — the
    /// reader is deciding whether to go now, and the number that answers that
    /// is how hard it will be running when they get there.
    var nextMax: (label: String, value: String, caption: String)? {
        guard let e = timeline.currentEvents
            .filter({ $0.kind != .slack && $0.time > scrubTime })
            .min(by: { $0.time < $1.time }) else { return nil }
        return ("Next max",
                "\(tilde)\(formatSpeed(abs(e.speed), unit: speedUnit))\u{00a0}\(speedUnitLabel(speedUnit))",
                "\(e.kind == .maxFlood ? "Flood" : "Ebb") at \(chartTime(e.time, tz))")
    }

    /// At a max the water is at its fastest; otherwise it is flooding or
    /// ebbing toward one. Snap targets land exactly on the event, hence the 1 s.
    private var atMax: CurrentEvent? {
        timeline.currentEvents.first { $0.kind != .slack && abs($0.time.timeIntervalSince(scrubTime)) < 1 }
    }

    private var state: String {
        if isSlack { return "Slack" }
        if let max = atMax { return max.kind == .maxFlood ? "Max flood" : "Max ebb" }
        return phase.word
    }

    var body: some View {
        let phaseColor = provisional ? SN.amber : CurrentDetailView.phaseColor(isSlack ? .slack : phase)
        LeadCard(value: Text("\(tilde)\(formatSpeed(abs(signed), unit: speedUnit))").font(ReadoutType.lead.monospacedDigit())
                    + Text(" \(speedUnitLabel(speedUnit))").font(ReadoutType.leadUnit),
                 time: chartTime(scrubTime, tz),
                 valueColor: readingColor,
                 timeColor: ink) {
            leadState(state, ink: ink)
            // The set is the hero (#59), arrow and point together after the
            // word. In slack the water goes both ways, so the glyph does too.
            HStack(spacing: 4) {
                if isSlack {
                    Image(systemName: "arrow.right.and.line.vertical.and.arrow.left")
                } else {
                    CompassArrow(deg: setDegrees)
                    Text(compass16(setDegrees))
                }
            }
            .foregroundStyle(phaseColor)
        }
    }
}

/// The scrub card both current details draw: the strip, the lead overlaid on
/// it, and the commentary walking to the next significant stop. One view, so
/// a harmonic station and an online gate can never drift a redesign apart the
/// way they did in #55.
struct CurrentScrubCard: View {
    let lead: CurrentLead
    let data: TimelineData
    let speedUnit: String
    let now: Date
    let floodDeg: Double
    let ebbDeg: Double
    let sky: SkyState
    @Binding var scrubTime: Date
    let onReturn: () -> Void

    var body: some View {
        // Asked once and captured: `nextSignificant` walks every window and
        // event, and the pill's label and its tap target must name the same
        // stop anyway.
        let next = lead.nextSignificant
        TimelineScrubStrip(data: data, geo: TimelineGeo(data: data),
                           speedUnit: speedUnit, now: now,
                           showsDayBands: false, chromeInk: sky.ink,
                           floodDeg: floodDeg, ebbDeg: ebbDeg,
                           scrubTime: $scrubTime, onReturn: onReturn,
                           commentary: lead.commentary,
                           onCommentary: { if let next { scrubTime = next.time } })
            .overlay(alignment: .top) { lead }
    }
}
