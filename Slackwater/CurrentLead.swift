// Slackwater — GPL v3. The current track's lead and commentary, one anatomy
// for every station with real velocities, harmonic or CHS-published: the
// speed as the hero, the set arrow and phase word above it, the time below,
// and the next significant stop the commentary pill walks to.
// Scrubber behavior here is specified in docs/scrubber.md: update the spec in the same change as any visible change.
import SwiftUI
import SlackwaterKit

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
    var bounded = false
    /// Where the next maximum stands among its own direction's maxima over the
    /// fortnight. Nil on an online gate, which has no fortnight to rank against.
    var standing: PeakStanding? = nil
    @AppStorage(setFormatKey, store: AppGroup.defaults) private var setFormat = "compass"

    private var isSlack: Bool { timeline.isSlack(at: scrubTime) }
    private var phase: CurrentPhase { currentPhase(signed: signed, inWindow: isSlack) }
    private var tilde: String { (provisional || bounded) ? "~" : "" }
    private var setDegrees: Double { signed >= 0 ? floodDeg : ebbDeg }
    private var readingColor: Color { (provisional || bounded) ? SN.amber : ink }

    /// The stops the commentary walks: a slack window's opening, the slack
    /// inside it, the window's closing, each max, and the sun's
    /// next rise or set when it beats all of them. The slack is its core's
    /// opening, or one stop at a core dot's centre or at a slack no core holds.
    /// A window too short to draw has no stops; the slack inside it does.
    var nextSignificant: CommentaryStop? {
        var slacks: [Date] = []
        for core in timeline.coreRuns {
            slacks.append(core.isDot ? core.centre : core.start)
        }
        slacks += timeline.bareSlackTimes
        var stops: [(time: Date, text: String)] = slacks.map { ($0, "Slack") }
        let seriesEnd = timeline.currentPoints.last?.time ?? .distantPast
        for run in timeline.windowRuns where !run.isDot {
            // A window and its core opening together are one stop, the slack.
            if !slacks.contains(run.start) {
                stops.append((run.start, "Slack window"))
            }
            // A run that reaches the series' end never closes.
            if run.end < seriesEnd && !timeline.isSlack(at: run.end) {
                stops.append((run.end, "Slack window closes"))
            }
        }
        for e in timeline.currentEvents where e.kind != .slack {
            stops.append((e.time, e.kind == .maxFlood ? "Max flood" : "Max ebb"))
        }
        let drawn = timeline.drawnSpan
        // The tilde belongs to the water's numbers, not to the sun's clock,
        // so it goes on here rather than in `commentary`.
        let water = stops.filter { commentaryCanName($0.time, after: scrubTime, drawn: drawn) }
            .min { $0.time < $1.time }
            .map { commentaryEventStop($0.text, at: $0.time, prefix: tilde) }
        return nextCommentaryStop(water, sun: timeline.days, after: scrubTime, drawn: drawn)
    }

    var commentary: CommentaryContent? {
        nextSignificant.map { commentaryContent($0, from: scrubTime) }
    }

    /// The summary tile's number: the maximum the water is heading for. A
    /// current's swing is the peak ahead, not a peak-to-peak span — the
    /// reader is deciding whether to go now, and the number that answers that
    /// is how hard it will be running when they get there.
    var nextMax: (label: String, value: String, caption: String)? {
        guard let e = timeline.currentEvents
            .filter({ $0.kind != .slack && $0.time > scrubTime })
            .min(by: { $0.time < $1.time }) else { return nil }
        return (String(localized: "Next max", comment: "Current summary label for the next maximum speed."),
                "\(tilde)\(formatSpeed(abs(e.speed), unit: speedUnit))\u{00a0}\(speedUnitLabel(speedUnit))",
                maxCaption(standing: standing, kind: e.kind, time: chartTime(e.time, tz)))
    }

    /// The maximum the tile is describing, and where it stands among its own
    /// direction's. Nil until the scan lands, and on an online gate for good:
    /// its detail holds about nine and a half days and a fortnight either side
    /// needs thirty.
    var nextMaxEvent: CurrentEvent? {
        timeline.currentEvents
            .filter { $0.kind != .slack && $0.time > scrubTime }
            .min { $0.time < $1.time }
    }

    /// At a max the water is at its fastest; otherwise it is flooding or
    /// ebbing toward one. Snap targets land exactly on the event, hence the 1 s.
    private var atMax: CurrentEvent? {
        timeline.currentEvents.first { $0.kind != .slack && abs($0.time.timeIntervalSince(scrubTime)) < 1 }
    }

    private var state: String {
        if isSlack { return String(localized: "Slack", comment: "Current phase: water is near zero speed.") }
        if let max = atMax {
            return max.kind == .maxFlood
                ? String(localized: "Max flood", comment: "Maximum flood-current state.")
                : String(localized: "Max ebb", comment: "Maximum ebb-current state.")
        }
        return phase.word
    }

    /// The lead in words, for the strip's spoken value: the set follows outside slack, as on the watch.
    var spoken: String {
        let reading = spokenReading(state, formatSpeed(abs(signed), unit: speedUnit), unit: speedUnitLabel(speedUnit))
        return isSlack ? reading : "\(reading) \(formatSet(setDegrees, format: setFormat))"
    }

    var body: some View {
        let phaseColor = (provisional || bounded) ? SN.amber : CurrentDetailView.phaseColor(phase)
        LeadCard(value: "\(tilde)\(formatSpeed(abs(signed), unit: speedUnit))",
                 unit: speedUnitLabel(speedUnit),
                 time: leadWhen(scrubTime, tz),
                 valueColor: readingColor,
                 timeColor: ink) {
            leadState(state, ink: ink)
            // The set is the hero (#59), arrow and point together after the
            // word. In slack the water goes both ways, so the glyph does too.
            HStack(spacing: 4) {
                if isSlack {
                    LeadGlyph(systemName: "arrow.right.and.line.vertical.and.arrow.left")
                } else {
                    LeadGlyph(systemName: "arrow.up", degrees: setDegrees)
                    // Unpinned, the eyebrow truncated "282°" to "28…" on iPhone 17.
                    Text(formatSet(setDegrees, format: setFormat)).fixedSize()
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
    let onResumeScrubbedAway: () -> Void
    /// Infinite-strip plumbing, nil on a fixed window (the online gate):
    /// governed y-scale, the store's scroll gate, viewport report.
    var scale: TimelineScale? = nil
    var scrollGate: ScrollGate? = nil
    var onViewportWidth: ((CGFloat) -> Void)? = nil

    var body: some View {
        // Asked once and captured: `nextSignificant` walks every window and
        // event, and the pill's label and its tap target must name the same
        // stop anyway.
        let next = lead.nextSignificant
        TimelineScrubStrip(data: data, geo: TimelineGeo(data: data, scale: scale),
                           speedUnit: speedUnit, now: now,
                           chromeInk: sky.ink,
                           floodDeg: floodDeg, ebbDeg: ebbDeg,
                           scrubTime: $scrubTime, onReturn: onReturn,
                           onResumeScrubbedAway: onResumeScrubbedAway,
                           spokenLead: lead.spoken,
                           commentary: lead.commentary,
                           onCommentary: { if let next { scrubTime = next.time } },
                           scrollGate: scrollGate,
                           onViewportWidth: onViewportWidth)
            .overlay(alignment: .top) { lead }
    }
}
