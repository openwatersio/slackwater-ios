// Slackwater — GPL v3. Tests for the continuous pan-under-centerline timeline
// (TimelineStrip.swift): fixed window and x↔time mapping, the now-readout
// equivalence with the old model's committed readout, night continuity across
// midnight, and the multi-day schedule window.
import SwiftUI
import XCTest
@testable import Slackwater
import TideEngine

final class TimelineTests: XCTestCase {
    let friday = TideStationRecord.all.first { $0.id == TideStationRecord.fridayHarborID }!

    func testSlackWindowSettingHasIncrementalTouchControls() throws {
        let source = try repoSource("Slackwater/SettingsView.swift")
        XCTAssertTrue(source.contains("Stepper(value: slackWindowSpeedBinding, in: 0.1...10, step: 0.1)"),
                      "Comfort current needs visible ± controls in 0.1-kn steps")
        XCTAssertFalse(source.contains("TextField(\"0.5\""),
                       "a bare text field makes the setting look non-interactive")
    }

    func testSlackWindowSpeedStaysInItsSupportedRange() {
        XCTAssertEqual(normalizedSlackThresholdKn(1), 1)
        XCTAssertEqual(normalizedSlackThresholdKn(0), defaultSlackThresholdKn)
        XCTAssertEqual(normalizedSlackThresholdKn(10.1), defaultSlackThresholdKn)
    }

    func testTimelineKeepsItsChosenSlackWindowSpeed() {
        let station = CurrentStationRecord.all.first!
        let timeline = TimelineData.build(tide: nil, current: station, now: Date(),
                                          anchor: todayLocal(station.tz), threshold: 1)
        XCTAssertEqual(timeline.slackThreshold, 1)
    }

    /// Calendar days, never `n * 86_400`. Only durations belong in
    /// `addingTimeInterval`: across a DST transition a 34×86,400-second offset
    /// from a local midnight lands at 01:00 or 23:00, and an anchor that isn't
    /// a midnight fails every assertion that compares one. Measured over 2026
    /// in Pacific, 68 of 365 start dates land off midnight — the suite was
    /// green today and red for roughly two months of the year.
    ///
    /// The calendar carries the STATION's zone, not the device's: a
    /// calendar-day add is only correct in the zone the dates belong to.
    private func addingDays(_ n: Int, to date: Date, in tz: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal.date(byAdding: .day, value: n, to: date)!
    }

    func testWindowAndMapping() {
        let now = Date()
        let d = TimelineData.build(tide: friday, current: nil, now: now, anchor: todayLocal(friday.tz))
        // -48h … +180h around today's local midnight (spec §2).
        XCTAssertEqual(d.end.timeIntervalSince(d.start), 228 * 3600, accuracy: 3601)
        XCTAssertEqual(d.totalWidth, 228 * Timeline.pph, accuracy: 13)
        XCTAssert(d.start <= now && now <= d.end)
        // x ↔ time round trip under the centerline.
        XCTAssertEqual(d.time(atX: d.x(now)).timeIntervalSince(now), 0, accuracy: 1)
        // Snap stops exist across the whole window (turns + sun events).
        XCTAssert(d.snapTimes.count > 20, "expected a full week of stops, got \(d.snapTimes.count)")
        XCTAssert(d.snapTimes.first! < d.today, "stops must reach back before today")
    }

    func testTideChevronCentersAreMagneticStops() {
        let fastest = TideStationRecord.all.max {
            $0.constituents.reduce(0) { $0 + $1.amplitude }
                < $1.constituents.reduce(0) { $0 + $1.amplitude }
        }!
        let d = TimelineData.build(tide: fastest, current: nil, now: Date(), anchor: todayLocal(fastest.tz))
        let chevrons = tideFlowArrows(d.tideRates).filter { $0.time >= d.start && $0.time <= d.end }
        XCTAssertFalse(chevrons.isEmpty)
        XCTAssertTrue(chevrons.allSatisfy { d.snapTimes.contains($0.time) })
    }

    func testFloatingReadoutMovesAwayFromTheCurve() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let data = TimelineData(tz: .current, anchor: t0, today: t0, start: t0,
                                end: t0.addingTimeInterval(3600), days: [], tidePoints: [],
                                tideRates: [], tideExtremes: [], currentPoints: [CurrentPoint(time: t0, speed: 1)],
                                currentEvents: [], snapTimes: [], slackWindows: [])
        let geo = TimelineGeo(data: data)
        XCTAssertGreaterThan(floatingReadoutY(pointY: geo.curTop, geo: geo), geo.curTop)
        XCTAssertLessThan(floatingReadoutY(pointY: geo.curBottom, geo: geo), geo.curBottom)
    }

    func testCurrentRangeIsPeakToPeakBetweenAdjacentMaxima() throws {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let events = [
            CurrentEvent(time: t0, speed: 2.4, kind: .maxFlood),
            CurrentEvent(time: t0.addingTimeInterval(3_600), speed: 0, kind: .slack),
            CurrentEvent(time: t0.addingTimeInterval(6_000), speed: -1.8, kind: .maxEbb),
        ]
        XCTAssertEqual(try XCTUnwrap(currentPeakToPeakRange(events, around: t0.addingTimeInterval(3_600))),
                       4.2, accuracy: 1e-9)
    }

    func testCurrentAxisUsesTheSelectedDisplayUnit() {
        XCTAssertEqual(currentAxisTicks(maxAbsKn: 2, unit: "kn"), [-2, -1, 0, 1, 2])
        XCTAssertEqual(currentAxisKnots(3.704, unit: "kmh"), 2, accuracy: 1e-9)
        XCTAssertEqual(currentAxisKnots(1.028888, unit: "ms"), 2, accuracy: 1e-9)
    }

    func testSixFeetPerHourTideRateIsRed() {
        XCTAssertEqual(Timeline.rampT(forTideRateMHr: 1.8), 1, accuracy: 1e-9)
        XCTAssertEqual(Timeline.rampT(forTideRateMHr: 6.1 / 3.28084), 1, accuracy: 1e-9)
    }

    func testTideRateWarningsFollowTheChevronSeverityBands() {
        XCTAssertEqual(tideRateSeverity(0.8), "⚠️ Fast")
        XCTAssertEqual(tideRateSeverity(1.2), "‼️ Very fast")
        XCTAssertEqual(tideRateSeverity(1.6), "🚨 Extreme")
        XCTAssertNil(tideRateSeverity(0.5))
    }

    func testChevronWarningsDoNotAppendTide() throws {
        XCTAssertFalse(try repoSource("Slackwater/TideDetailView.swift").contains("\\(severity) \\(direction) tide"))
    }

    func testCurrentHeadersLeadWithPlainLanguageAndRestoreNow() throws {
        let current = try repoSource("Slackwater/CurrentDetailView.swift")
        let online = try repoSource("Slackwater/OnlineGateDetailView.swift")
        let strip = try repoSource("Slackwater/TimelineStrip.swift")
        XCTAssertTrue(current.contains("\\(phase.gloss?.capitalized ?? phase.word) · \\(phase.word)"))
        XCTAssertTrue(online.contains("\\(phase.gloss?.capitalized ?? phase.word) · \\(phase.word)"))
        XCTAssertTrue(strip.contains("scrubbedAway(scrubTime, from: now)"))
        XCTAssertTrue(strip.contains("detail-return-now"))
    }

    func testOnlineGatesShareTheDownloadSurfaceAndCopy() throws {
        let manager = try repoSource("Slackwater/OfflineDownloads.swift")
        let detail = try repoSource("Slackwater/OnlineGateDetailView.swift")
        XCTAssertTrue(manager.contains("case .online(let gate): onlineRow(gate)"))
        XCTAssertTrue(manager.contains(".onChange(of: net.online)"))
        XCTAssertTrue(detail.contains("Button(\"Refresh\")"))
        XCTAssertFalse(detail.contains("No offline prediction here"))
    }

    /// `now:` used to be a dead parameter — `today` was always derived from the
    /// real clock (`todayLocal(tz)`) regardless of what was passed in. A caller
    /// simulating a different day (a test, or a future date-picker caller) must
    /// get back ITS day, not the device's.
    func testTodayDerivesFromThePassedNowNotTheRealClock() {
        let tz = friday.tz
        let simulatedNow = todayLocal(tz).addingTimeInterval(5 * 86_400 + 3600)  // 5 days ahead, mid-morning
        let d = TimelineData.build(tide: friday, current: nil, now: simulatedNow, anchor: todayLocal(tz))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        XCTAssertEqual(d.today, cal.startOfDay(for: simulatedNow),
                       "today must follow the passed `now`, not the real clock")
    }

    /// The anchor drives geometry; `today` stays the real day. A September strip
    /// must be built around September and still know what day it actually is.
    func testFutureAnchorMovesTheWindowButNotToday() {
        let now = Date()
        let tz = friday.tz
        let today = todayLocal(tz)
        let future = addingDays(34, to: today, in: tz)

        let d = TimelineData.build(tide: friday, current: nil, now: now, anchor: future)
        XCTAssertEqual(d.anchor, future)
        XCTAssertEqual(d.today, today, "today is the real day, not the anchor")
        XCTAssertEqual(d.start, future.addingTimeInterval(-Timeline.backHours * 3600),
                       "the 48h back-pad is unconditional (#67 item 1)")
        XCTAssertEqual(d.end.timeIntervalSince(d.start), (Timeline.backHours + 180) * 3600, accuracy: 3601)
        XCTAssert(d.tidePoints.allSatisfy { $0.time >= d.start && $0.time <= d.end })
    }

    func testContainsBoundsTheStripWindow() {
        let tz = friday.tz
        let today = todayLocal(tz)
        let now = Date()
        let d = TimelineData.build(tide: friday, current: nil, now: now, anchor: today)
        XCTAssert(d.contains(now), "a today-anchored strip contains now")

        let ahead = TimelineData.build(tide: friday, current: nil, now: now,
                                       anchor: addingDays(34, to: today, in: tz))
        XCTAssertFalse(ahead.contains(now),
                       "a September strip must not claim to hold today's now-marker")
        XCTAssert(ahead.contains(ahead.anchor.addingTimeInterval(3 * 86_400)))
    }

    /// `days` must reach one day PAST the last visible night — `drawDayChrome`
    /// reads day+1's sunrise to place the moon mid-night — and far enough BACK
    /// that the day containing `start` was built, which is what `visibleDays`
    /// needs to decide what draws.
    ///
    /// Both stated against the window, never against the literal range. This
    /// test used to pin `days.first?.offset == -2` and `.last?.offset == 8`,
    /// and the -2 went red the moment the range legitimately widened to -3: a
    /// bound of `dayChrome`'s own array is an implementation detail, not a
    /// property anything depends on. What IS depended on is that the array
    /// covers the window at both ends.
    ///
    /// The March pair keeps the backward half honest year-round. On the two
    /// anchors following a spring-forward the 48h look-back reaches an hour
    /// into the THIRD calendar day back, because the day between them is only
    /// 23 hours long — narrow the range to -2 again and this fails on any day
    /// of the year, not just in March. `anchor` alone drives `start`/`end`/`days`
    /// (the back-pad is unconditional, #67 item 1), so the custom `now` here
    /// only keeps `today` sane for a March date — it plays no part in exercising
    /// the -3-day spread.
    func testDayChromeCoversTheLastNightsMoon() {
        let springForwardPlusOne = vancouverMidnight(2026, 3, 9)
        for (anchor, now) in [(todayLocal(friday.tz), Date()),
                              (springForwardPlusOne, springForwardPlusOne.addingTimeInterval(9 * 3600))] {
            let d = TimelineData.build(tide: friday, current: nil, now: now, anchor: anchor)

            XCTAssertNotNil(d.day(of: d.start),
                            "no built day contains the strip's start (anchor \(anchor))")

            let lastNight = d.visibleDays.last!
            let nextDay = d.days.first { $0.offset == lastNight.offset + 1 }
            XCTAssertNotNil(nextDay,
                            "the last visible night has no following day (anchor \(anchor))")
            XCTAssertNotNil(lastNight.sunset)
            XCTAssertNotNil(nextDay?.sunrise,
                            "the last visible night needs the next day's sunrise for its moon")
        }
    }

    /// "Today" must mean today, on any strip. The old signature took a
    /// days-from-today offset; once the anchor moves, offset is days-from-ANCHOR
    /// and passing it here would label a September Monday "Today".
    func testRelativeDayLabelTracksTodayNotTheAnchor() {
        let tz = TimeZone(identifier: "America/Vancouver")!
        let today = vancouverMidnight(2026, 8, 11)          // a Tuesday
        let tomorrow = vancouverMidnight(2026, 8, 12)
        let yesterday = vancouverMidnight(2026, 8, 10)
        let september = vancouverMidnight(2026, 9, 14)      // a Monday

        XCTAssertEqual(relativeDayLabel(today, tz, today: today), "Today")
        XCTAssertEqual(relativeDayLabel(tomorrow, tz, today: today), "Tomorrow")
        XCTAssertEqual(relativeDayLabel(yesterday, tz, today: today), "Yesterday")
        XCTAssertEqual(relativeDayLabel(september, tz, today: today), "Mon",
                       "a day 34 days out is a weekday, never Today")
    }

    /// The first group of a future-anchored schedule is the anchor's own day, and
    /// it must NOT be called Today.
    func testFutureAnchorFirstDayIsNotLabelledToday() {
        let tz = friday.tz
        let today = todayLocal(tz)
        let future = addingDays(34, to: today, in: tz)
        let d = TimelineData.build(tide: friday, current: nil, now: Date(), anchor: future)
        let firstDay = d.days.first { $0.offset == 0 }!
        XCTAssertEqual(firstDay.start, future, "offset 0 is the ANCHOR's day")
        XCTAssertNotEqual(relativeDayLabel(firstDay.start, tz, today: today), "Today")
    }

    /// The list runs the anchor's 00:00 → +7 local calendar days, and it is
    /// strictly inside the strip — even when DST makes that week 167h or 169h.
    func testScheduleRangeIsSevenLocalDaysAcrossDST() {
        let tz = friday.tz
        for (anchor, hours) in [(vancouverMidnight(2026, 3, 8), 167.0),
                                (vancouverMidnight(2026, 11, 1), 169.0)] {
            let d = TimelineData.build(tide: friday, current: nil, now: Date(), anchor: anchor)
            XCTAssertEqual(d.scheduleRange.lowerBound, anchor)
            XCTAssertEqual(d.scheduleRange.upperBound, addingDays(7, to: anchor, in: tz))
            XCTAssertEqual(d.scheduleRange.upperBound.timeIntervalSince(anchor) / 3600, hours)
            XCTAssertLessThan(d.scheduleRange.upperBound, d.end,
                              "the strip must outrun the list by the centerPad")
        }
    }

    /// Seven day-groups, and the first is the anchor's own day.
    func testFutureAnchorSchedulesSevenDays() {
        let tz = friday.tz
        let future = addingDays(34, to: todayLocal(tz), in: tz)
        let d = TimelineData.build(tide: friday, current: nil, now: Date(), anchor: future)
        let turns = d.tideExtremes.filter { d.scheduleRange.contains($0.time) }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let days = Set(turns.map { cal.startOfDay(for: $0.time) })
        XCTAssertEqual(days.count, 7, "a week of tide turns, got \(days.count)")
        XCTAssertEqual(days.min(), future)
    }

    // MARK: - The window (spec §1, §2)

    private func vancouverMidnight(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Vancouver")!
        return cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    /// #67 item 1: every window carries the 48h look-back — today's answers "what
    /// did the water just do"; a picked week's puts data behind the noon park
    /// (216pt in), which otherwise opens on dead space on any pane wider than
    /// 432pt (UIScrollView clamps the negative centering offset). One
    /// unconditional shape also deletes the anchor == today exact-equality trap
    /// three comment blocks used to guard.
    func testWindowBackPadIsUnconditional() {
        let today = vancouverMidnight(2026, 8, 11)
        let current = Timeline.window(anchor: today)
        XCTAssertEqual(current.start, today.addingTimeInterval(-48 * 3600))
        XCTAssertEqual(current.end, today.addingTimeInterval(180 * 3600))

        let future = vancouverMidnight(2026, 9, 14)
        let ahead = Timeline.window(anchor: future)
        XCTAssertEqual(ahead.start, future.addingTimeInterval(-48 * 3600),
                       "a picked week gets the same look-back as today's")
        XCTAssertEqual(ahead.end, future.addingTimeInterval(180 * 3600))

        let past = vancouverMidnight(2026, 7, 6)
        let behind = Timeline.window(anchor: past)
        XCTAssertEqual(behind.start, past.addingTimeInterval(-48 * 3600),
                       "a past anchor gets the same look-back as today's")
        XCTAssertEqual(behind.end, past.addingTimeInterval(180 * 3600))
    }

    /// The strip must stay WIDER than the list, or tapping the last schedule row
    /// lands the centerline short of the event it names (UIScrollView clamps
    /// contentOffset). The pad is what guarantees it.
    func testStripOutrunsTheScheduleByTheCenterPad() {
        XCTAssertEqual(Timeline.scheduleHours, 168, "a week in the list")
        XCTAssertEqual(Timeline.forwardHours, Timeline.scheduleHours + Timeline.centerPad)
        XCTAssertGreaterThan(Timeline.centerPad * Timeline.pph, 200,
                             "the pad must exceed half a phone's width in points")
    }

    func testTodayLocalIsMidnightInTheGivenZone() {
        let tz = TimeZone(identifier: "America/Vancouver")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let t = todayLocal(tz)
        XCTAssertEqual(t, cal.startOfDay(for: appNow()))
        XCTAssertEqual(cal.component(.hour, from: t), 0)
    }

    /// The centerline readout at "now" must equal the old model's now-readout:
    /// both are the same engine step-1 heights call. The strip's riding dot
    /// (10-min interpolation) must agree within rendering tolerance.
    func testNowReadoutEquivalence() {
        let now = Date()
        let engine = friday.engineStation
            .heights(from: now, to: now.addingTimeInterval(1), step: 1).first!.height
        let d = TimelineData.build(tide: friday, current: nil, now: now, anchor: todayLocal(friday.tz))
        XCTAssertEqual(d.heightAt(now), engine, accuracy: 0.02)
        print("NOW-READOUT Friday Harbor @ \(now): engine=\(engine) m, strip=\(d.heightAt(now)) m")
    }

    /// Days bleed into each other: every night band runs sunset → next
    /// sunrise, straddling the midnight between them.
    func testNightContinuityAcrossMidnight() {
        let d = TimelineData.build(tide: friday, current: nil, now: Date(), anchor: todayLocal(friday.tz))
        var checked = 0
        for (a, b) in zip(d.days, d.days.dropFirst()) {
            guard let set = a.sunset, let rise = b.sunrise else { continue }
            XCTAssert(set < b.start && b.start < rise,
                      "night must straddle midnight: \(set) … \(rise)")
            checked += 1
        }
        XCTAssertGreaterThanOrEqual(checked, 7)
    }

    /// Day chrome draws every day the strip touches, and nothing else draws a
    /// snap stop. The filter behind `drawDayChrome` was a literal `offset <= 5`
    /// left over from the 132h strip: days 6 and 7 of the week drew no night
    /// band, no tint, no label and no sun dots, while their sun events stayed
    /// in `snapTimes` — the magnet parked the centerline on a sunrise drawn
    /// nowhere, silently. So this asserts the RELATIONSHIP to the window, never
    /// The day band's edge is the next local midnight, not start + 86,400: on a
    /// DST transition the local day is 25 h (fall back) or 23 h (spring forward)
    /// and the duration bound misdraws the band by an hour (#62).
    func testDayEndIsExactAcrossDSTTransitions() {
        let tz = friday.tz  // America/Los_Angeles — both 2026 transitions
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        for (ymd, hours) in [((2026, 11, 1), 25.0), ((2026, 3, 8), 23.0)] {
            let anchor = cal.date(from: DateComponents(year: ymd.0, month: ymd.1, day: ymd.2))!
            let d = TimelineData.build(tide: friday, current: nil, now: anchor, anchor: anchor)
            let day = d.day(of: anchor)!
            XCTAssertEqual(day.start, anchor, "anchor must be the transition day's midnight")
            XCTAssertEqual(d.dayEnd(day).timeIntervalSince(day.start), hours * 3600,
                           "the \(ymd) local day is \(hours) hours")
        }
    }

    /// a literal offset range, and it must survive a change to `forwardHours`.
    func testVisibleDaysFollowTheWindowNotAFixedOffset() {
        let tz = friday.tz
        for anchor in [todayLocal(tz), addingDays(-7, to: todayLocal(tz), in: tz)] {
            let d = TimelineData.build(tide: friday, current: nil, now: Date(), anchor: anchor)
            let visible = d.visibleDays
            let drawn = Set(visible.map(\.offset))
            XCTAssertFalse(drawn.isEmpty)

            // Drawn ⟺ the day overlaps the window. `days` is contiguous, so a
            // day ends where the next begins (exact across DST, unlike +86400).
            for day in d.days {
                let overlaps = day.start <= d.end && d.dayEnd(day) > d.start
                XCTAssertEqual(drawn.contains(day.offset), overlaps,
                               "day \(day.offset) (anchor \(anchor)): overlaps=\(overlaps), drawn=\(drawn.contains(day.offset))")
            }
            // No gap at either end: chrome opens on or before the window and
            // runs past its end.
            XCTAssert(visible.first!.start <= d.start)
            XCTAssert(visible.last!.start <= d.end)
            XCTAssert(d.dayEnd(visible.last!) >= d.end,
                      "the last drawn day must reach the end of the strip")
            // The original failure, stated directly: a day that draws nothing
            // must contribute no snap stop.
            for day in d.days where !drawn.contains(day.offset) {
                for t in [day.sunrise, day.sunset].compactMap({ $0 }) {
                    XCTAssertFalse(d.snapTimes.contains { abs($0.timeIntervalSince(t)) < 1 },
                                   "day \(day.offset) draws no chrome, so \(t) must not be a snap stop")
                }
            }
        }
    }

    /// The schedule window (the anchor's midnight → +7d) spans at least two
    /// local days of tide turns — the rolling multi-day list. Asked of
    /// `scheduleRange`, the one definition the list itself filters on; the
    /// hand-built `today ± hours` version here only agreed by accident of
    /// `anchor == today`.
    func testScheduleWindowSpansMultipleDays() {
        let d = TimelineData.build(tide: friday, current: nil, now: Date(), anchor: todayLocal(friday.tz))
        let turns = d.tideExtremes.filter { d.scheduleRange.contains($0.time) }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = d.tz
        let days = Set(turns.map { cal.startOfDay(for: $0.time) })
        XCTAssertGreaterThanOrEqual(days.count, 2)
    }

    /// The strip is 12-hour with a bare lowercase suffix; the schedule stays
    /// 24-hour and zero-padded. Both facts matter and pinning them apart is the
    /// point: the schedule's times are a left-aligned monospaced column where
    /// the pad keeps the colons in line and a suffix only some rows carry would
    /// ragged it, while the strip centres each label on its own event and pays
    /// for every character it prints.
    func testChartTimeIsBareTwelveHourAndClockTimeStaysPadded() {
        var cal = Calendar(identifier: .gregorian)
        let utc = TimeZone(identifier: "UTC")!
        cal.timeZone = utc
        func at(_ h: Int, _ m: Int) -> Date {
            cal.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: h, minute: m))!
        }
        XCTAssertEqual(chartTime(at(7, 3), utc), "7:03am", "no pad, bare lowercase suffix")
        XCTAssertEqual(clockTime(at(7, 3), utc), "07:03", "the schedule column keeps its pad")
        XCTAssertEqual(chartTime(at(16, 22), utc), "4:22pm")
        XCTAssertEqual(clockTime(at(16, 22), utc), "16:22")
        // The two ends of the clock, where 12-hour conversion goes wrong:
        // midnight is 12am and noon is 12pm, never 0am/0pm and never each other.
        XCTAssertEqual(chartTime(at(0, 36), utc), "12:36am")
        XCTAssertEqual(chartTime(at(12, 5), utc), "12:05pm")
        XCTAssertEqual(chartTime(at(23, 59), utc), "11:59pm")
        // No space and no periods — " p.m." is four characters the strip can't spend.
        XCTAssertFalse(chartTime(at(16, 22), utc).contains(" "))
        XCTAssertFalse(chartTime(at(16, 22), utc).contains("."))
    }

    /// EVERY time the strip prints must be a time the strip can stop on.
    ///
    /// The magnet snaps to `snapTimes`, so a label showing anything else puts a
    /// number on screen that the scrubber will never park you at. The slack
    /// label printed its WINDOW'S OPENING EDGE for one iteration and that edge
    /// is not a snap stop — you read "7:48pm", let go, and landed on 7:56pm
    /// with nothing explaining the gap.
    ///
    /// Window edges are labelled as the start/end of the usable window, so
    /// they need to be valid stops too.
    func testEveryLabelledTimeIsSomethingTheMagnetCanStopOn() throws {
        let victoria = CurrentStationRecord.all.first { !$0.isChs } ?? CurrentStationRecord.all[0]
        let d = TimelineData.build(tide: nil, current: victoria, now: Date(), anchor: todayLocal(victoria.tz))
        let stops = Set(d.snapTimes)
        XCTAssertFalse(stops.isEmpty, "no snap stops — the rest of this proves nothing")

        let slacks = d.currentEvents.filter { $0.kind == .slack && $0.time >= d.start && $0.time <= d.end }
        XCTAssertFalse(slacks.isEmpty, "no slacks at this station — pick another fixture")
        for e in slacks {
            XCTAssert(stops.contains(e.time),
                      "the strip labels slack at \(e.time) but the magnet cannot stop there")
        }
        // Maxes are labelled too, and they are snap stops for the same reason.
        for e in d.currentEvents where e.kind != .slack && e.time >= d.start && e.time <= d.end {
            XCTAssert(stops.contains(e.time),
                      "the strip labels a max at \(e.time) but the magnet cannot stop there")
        }

        let windows = d.slackWindows.filter { $0.start >= d.start && $0.end <= d.end }
        XCTAssertFalse(windows.isEmpty, "no windows at this station — pick another fixture")
        for window in windows {
            XCTAssert(stops.contains(window.start))
            XCTAssert(stops.contains(window.end))
        }
    }

    /// Two single-track geometries, no combined case (split-scrubbers spec §1/§2).
    func testSingleTrackGeometries() {
        let tideData = TimelineData.build(tide: friday, current: nil, now: Date(), anchor: todayLocal(friday.tz))
        let tide = TimelineGeo(data: tideData)
        XCTAssert(tide.hasTide && !tide.hasCurrent)
        // One plot box for either track (card-look spec §2): the readings
        // live on the curve and one time row under it, so there is nothing
        // left to size differently. Asserted as structure, not pixels.
        XCTAssertEqual(tide.bodyTop, tide.tideTop)
        XCTAssertEqual(tide.bodyBottom, tide.tideBottom)
        XCTAssertGreaterThan(tide.bodyTop, tide.sunY + 8 + 8, "the plot clears the moon disc")
        XCTAssertGreaterThan(tide.timeY, tide.bodyBottom + 8, "the time row sits under the plot")
        XCTAssertLessThan(tide.timeY, tide.height - 8, "and inside the canvas")

        // Current-only: construct TimelineData directly — the geometry keys only
        // on which point arrays are non-empty.
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let cur = TimelineGeo(data: TimelineData(
            tz: .current, anchor: t0, today: t0, start: t0, end: t0.addingTimeInterval(3600),
            days: [], tidePoints: [], tideRates: [], tideExtremes: [],
            currentPoints: [CurrentPoint(time: t0, speed: 1)], currentEvents: [],
            snapTimes: [], slackWindows: []))
        XCTAssert(!cur.hasTide && cur.hasCurrent)
        XCTAssertEqual(cur.bodyTop, cur.curTop)
        XCTAssertEqual(cur.bodyBottom, cur.curBottom)
        XCTAssertEqual(cur.height, tide.height, "same canvas for both tracks")
        XCTAssertEqual(cur.curTop, tide.tideTop, "same plot box for both tracks")
        XCTAssertEqual(cur.curBottom, tide.tideBottom)
        XCTAssertEqual(cur.timeY, tide.timeY)

        // Both arrays non-empty: pins that no case (true, true) exists to claim
        // it — resurrecting the deleted combined arm ahead of `case (true, _)`
        // would go uncaught otherwise. TidePoint has no public init outside
        // TideEngine, so the tide side is real data borrowed from the tide-only
        // build above; only the current side is synthesized.
        let both = TimelineGeo(data: TimelineData(
            tz: tideData.tz, anchor: tideData.anchor, today: tideData.today, start: tideData.start, end: tideData.end,
            days: tideData.days, tidePoints: tideData.tidePoints, tideRates: tideData.tideRates,
            tideExtremes: tideData.tideExtremes,
            currentPoints: [CurrentPoint(time: tideData.start, speed: 1)], currentEvents: [],
            snapTimes: tideData.snapTimes, slackWindows: []))
        XCTAssert(both.hasTide && both.hasCurrent)
        XCTAssertEqual(both.height, tide.height,
                       "combined input resolves tide-first — no combined case exists (spec §1/§2)")
        XCTAssertEqual(both.curTop, 0)
    }

    /// The tide track draws the card's curve: the card's blue fill, no
    /// speed palette in the fill, and the tide-rate ramp carried by the
    /// LINE COLOUR rather than by chevron glyphs (card-look spec §4).
    func testTideTrackUsesCardFillAndRateColouredLine() throws {
        let source = try repoSource("Slackwater/TimelineStrip.swift")
        let lines = source.components(separatedBy: .newlines)
        guard let start = lines.firstIndex(where: { $0.contains("private func drawTide(") }),
              let end = lines[(start + 1)...].firstIndex(where: { $0.contains("private func deg(") })
        else { return XCTFail("drawTide body not found") }
        let body = lines[start..<end].joined(separator: "\n")

        XCTAssertFalse(body.contains("currentFillStops"), "tide fill must not use the current speed palette")
        XCTAssertTrue(body.contains("SN.graphLine.opacity(CurveStyle.fillOpacity)"), "tide fill is the card's blue gradient")
        XCTAssertFalse(body.contains("››››"), "chevrons are gone; the line carries the rate")
        XCTAssertTrue(body.contains("tideRateStops("), "the stroke takes its colour from the tide-rate ramp")
    }

    /// Below the ramp floor the line is the base colour; above it the stroke
    /// follows the absolute tide-rate ramp, so a lazy tide never leaves blue
    /// and a Fundy run reaches red.
    func testTideRateStopsColourOnlyFastWater() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let x = { (t: Date) -> CGFloat in CGFloat(t.timeIntervalSince(t0)) }
        let lazy = [(time: t0, rate: 0.2), (time: t0.addingTimeInterval(100), rate: -0.5)]
        XCTAssertTrue(tideRateStops(lazy, x: x, width: 100).allSatisfy { $0.color == SN.graphLine })

        let fundy = [(time: t0, rate: 0.2),
                     (time: t0.addingTimeInterval(50), rate: 1.8),
                     (time: t0.addingTimeInterval(100), rate: 0.2)]
        let stops = tideRateStops(fundy, x: x, width: 100)
        XCTAssertEqual(stops[0].color, SN.graphLine)
        XCTAssertEqual(stops[1].color, SN.speedColour(1), "1.8 m/hr is the red ceiling")
        XCTAssertEqual(stops[2].color, SN.graphLine)
        XCTAssertEqual(stops[1].location, 0.5, accuracy: 0.001)
    }

    /// v falls linearly 2 kn → -2 kn over 2 h (slack at +60 min); |v| < 0.5
    /// between +45 and +75 min. Samples every 10 min like the drawn series.
    func testSlackWindowInterpolatesCrossings() throws {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let pts = (0...12).map { i in
            CurrentPoint(time: t0.addingTimeInterval(Double(i) * 600),
                         speed: 2.0 - Double(i) / 3.0)
        }
        let w = try XCTUnwrap(slackWindow(pts, around: t0.addingTimeInterval(3600),
                                          threshold: 0.5))
        XCTAssertEqual(w.start.timeIntervalSince(t0), 2700, accuracy: 1)
        XCTAssertEqual(w.end.timeIntervalSince(t0), 4500, accuracy: 1)
    }

    /// A series that never leaves the window clamps to its edges.
    func testSlackWindowClampsToSeriesEdges() throws {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let pts = (0...6).map { CurrentPoint(time: t0.addingTimeInterval(Double($0) * 600), speed: 0.1) }
        let w = try XCTUnwrap(slackWindow(pts, around: t0.addingTimeInterval(1800), threshold: 0.5))
        XCTAssertEqual(w.start, pts.first!.time)
        XCTAssertEqual(w.end, pts.last!.time)
    }

    func testSlackWindowIncludesAnExactThresholdPoint() throws {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let points = [
            CurrentPoint(time: t0, speed: 2),
            CurrentPoint(time: t0.addingTimeInterval(600), speed: 1),
            CurrentPoint(time: t0.addingTimeInterval(1200), speed: 2),
        ]
        let window = try XCTUnwrap(slackWindow(points, around: points[1].time, threshold: 1))
        XCTAssertEqual(window.start, points[1].time)
        XCTAssertEqual(window.end, points[1].time)
    }

    /// No sub-threshold sample brackets the slack (a violent gate where the
    /// 10-min sampling steps over the window) — no window, not a wrong one.
    func testSlackWindowNilWhenSamplingStepsOver() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let pts = (0...4).map { i in
            CurrentPoint(time: t0.addingTimeInterval(Double(i) * 600),
                         speed: i < 2 ? 4.0 : -4.0)
        }
        XCTAssertNil(slackWindow(pts, around: t0.addingTimeInterval(900), threshold: 0.5))
    }

    /// A slack outside the sampled series has no window. Events are scanned with a
    /// ±6h pad beyond the strip and the points are clipped to it, so this case is
    /// reachable at both edges — and it used to return a window sitting entirely
    /// before its own slack.
    func testSlackOutsideTheSeriesHasNoWindow() {
        let t0 = Date(timeIntervalSince1970: 1_760_000_000)
        let pts = (0...5).map { i in
            CurrentPoint(time: t0.addingTimeInterval(Double(i) * 600), speed: 0.1)
        }
        XCTAssertNil(slackWindow(pts, around: t0.addingTimeInterval(-3600), threshold: 0.5),
                     "a slack before the series has no window")
        XCTAssertNil(slackWindow(pts, around: t0.addingTimeInterval(6 * 3600), threshold: 0.5),
                     "a slack after the series must not borrow the trailing run")
    }

    func testCurrentExcessSegmentsStartAtTheSlackThreshold() {
        let t0 = Date(timeIntervalSince1970: 1_760_000_000)
        let points = [
            CurrentPoint(time: t0, speed: -2),
            CurrentPoint(time: t0.addingTimeInterval(600), speed: -0.5),
            CurrentPoint(time: t0.addingTimeInterval(1200), speed: 0.5),
            CurrentPoint(time: t0.addingTimeInterval(1800), speed: 2),
        ]

        let segments = currentExcessSegments(points, threshold: 1)

        XCTAssertEqual(segments.map { $0.map(\.speed) }, [[-2, -1], [1, 2]])
        XCTAssertEqual(segments[0][1].time, t0.addingTimeInterval(400))
        XCTAssertEqual(segments[1][0].time, t0.addingTimeInterval(1400))
    }

    /// The window computation is build-time data now, not a per-view recompute
    /// (gutter spec §3) — so the band on the strip and the duration in the
    /// readout are the same numbers by construction.
    func testSlackWindowsBracketTheirSlacks() throws {
        let station = try XCTUnwrap(CurrentStationRecord.all.first)
        let d = TimelineData.build(tide: nil, current: station, now: Date(), anchor: todayLocal(station.tz))
        let slacks = d.currentEvents.filter { $0.kind == .slack }
        XCTAssertGreaterThan(slacks.count, 10, "a week of slacks must exist to window")
        XCTAssertFalse(d.slackWindows.isEmpty)
        for w in d.slackWindows {
            XCTAssert(w.start <= w.slack && w.slack <= w.end,
                      "a window must bracket its own slack: \(w)")
            XCTAssert(slacks.contains { $0.time == w.slack },
                      "every window belongs to a drawn slack event")
        }
    }

    func testSlackWindowEdgesAreMagneticPoints() throws {
        let station = try XCTUnwrap(CurrentStationRecord.all.first)
        let timeline = TimelineData.build(tide: nil, current: station, now: Date(),
                                          anchor: todayLocal(station.tz), threshold: 1)
        let window = try XCTUnwrap(timeline.slackWindows.first)
        XCTAssertTrue(timeline.snapTimes.contains(window.start))
        XCTAssertTrue(timeline.snapTimes.contains(window.end))
    }

    func testSlackWindowContainingTimeIncludesBothEdges() throws {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let window = (slack: t0.addingTimeInterval(1_200),
                      start: t0.addingTimeInterval(300),
                      end: t0.addingTimeInterval(2_400))
        let timeline = TimelineData(tz: .gmt, anchor: t0, today: t0, start: t0,
                                    end: t0.addingTimeInterval(3_600), days: [],
                                    tidePoints: [], tideRates: [], tideExtremes: [],
                                    currentPoints: [], currentEvents: [], snapTimes: [],
                                    slackWindows: [window])

        XCTAssertEqual(try XCTUnwrap(timeline.containingSlackWindow(at: window.start)).slack,
                       window.slack)
        XCTAssertEqual(try XCTUnwrap(timeline.containingSlackWindow(at: window.slack)).slack,
                       window.slack)
        XCTAssertEqual(try XCTUnwrap(timeline.containingSlackWindow(at: window.end)).slack,
                       window.slack)
        XCTAssertNil(timeline.containingSlackWindow(at: window.start.addingTimeInterval(-1)))
        XCTAssertNil(timeline.containingSlackWindow(at: window.end.addingTimeInterval(1)))
    }

    func testSlackWindowTimingHumanizesOnlyUsefulDurations() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .gmt
        let start = cal.date(from: DateComponents(year: 2026, month: 8, day: 25,
                                                  hour: 11, minute: 25))!

        XCTAssertEqual(slackWindowTiming(start: start, end: start.addingTimeInterval(35 * 60), tz: .gmt).duration,
                       "35 min")
        XCTAssertEqual(slackWindowTiming(start: start, end: start.addingTimeInterval(89 * 60), tz: .gmt).duration,
                       "~1 hr")
        XCTAssertEqual(slackWindowTiming(start: start, end: start.addingTimeInterval(134 * 60), tz: .gmt).duration,
                       "~2 hrs")
        XCTAssertNil(slackWindowTiming(start: start, end: start.addingTimeInterval(150 * 60), tz: .gmt).duration)
    }

    func testSlackWindowTimingMarksLaterDays() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .gmt
        let start = cal.date(from: DateComponents(year: 2026, month: 8, day: 25,
                                                  hour: 21, minute: 35))!
        let end = { (day: Int) in
            cal.date(byAdding: DateComponents(day: day, minute: 19),
                     to: cal.startOfDay(for: start))!
        }

        XCTAssertEqual(slackWindowTiming(start: start, end: end(1), tz: .gmt).span,
                       "21:35 → 00:19⁺¹")
        XCTAssertEqual(slackWindowTiming(start: start, end: end(9), tz: .gmt).span,
                       "21:35 → 00:19⁺⁹")
        XCTAssertEqual(slackWindowTiming(start: start, end: end(10), tz: .gmt).span,
                       "21:35 → 00:19⁺⁺")
    }

    /// A derived gate's curve is a schematic ±1 SHAPE, not a velocity, so a
    /// 0.5 kn window measured off it would be fiction (gutter spec §3). Its
    /// slacks fall back to a plain dropline instead.
    func testDerivedGateHasNoSlackWindows() throws {
        let port = TideStationRecord(
            id: "chs-point-atkinson", name: "Point Atkinson", region: "West Vancouver",
            aliases: [], latitude: 49.337, longitude: -123.254,
            timezone: "America/Vancouver", chartDatum: "Chart", datumOffset: 3.0,
            constituents: [.init(name: "M2", amplitude: 1.5, phase: 0)])
        let gate = DerivedGateRecord(gate: ChsGateInfo.all.first { $0.id == "chs-malibu-rapids" }!,
                                     port: port)
        let d = TimelineData.build(gate: gate, now: Date(), anchor: todayLocal(gate.gate.tz))
        XCTAssert(d.hasCurrent, "the schematic track exists")
        XCTAssertFalse(d.currentEvents.isEmpty, "the gate has slack events")
        XCTAssert(d.slackWindows.isEmpty, "but no windows — the curve is a shape (gutter spec §3)")
    }

    /// The strip is wider than one Metal texture. A `Canvas` is a single
    /// backing layer capped at 8192px per side, and the whole chart renders
    /// EMPTY past it — silently, no error, which is why this needs a test and
    /// not a comment. Widening `pph` from 12 to 18 crossed it on a 3× phone
    /// (9720px) and blanked every tide detail; the tiles exist to keep each
    /// layer under the cap, so the assertion is on a tile, not on the strip.
    func testCanvasTilesStayUnderTheTextureCap() {
        let d = TimelineData.build(tide: friday, current: nil, now: Date(), anchor: todayLocal(friday.tz))
        let cap: CGFloat = 8192
        let scale: CGFloat = 3        // the densest screen this ships to

        XCTAssertGreaterThan(d.totalWidth * scale, cap,
                             "if the whole strip fits in one texture the tiling is dead code — delete it, don't keep an untested branch")
        XCTAssertLessThan(TimelineCanvas.tileWidth * scale, cap,
                          "a tile must fit in one texture at 3×")
        XCTAssertLessThan(TimelineGeo(data: d).height * scale, cap,
                          "and so must its height")
        // Whole points at every scale factor: a fractional boundary antialiases
        // against transparent on both sides and leaves a hairline seam.
        for s in [1.0, 2.0, 3.0] as [CGFloat] {
            XCTAssertEqual((TimelineCanvas.tileWidth * s).truncatingRemainder(dividingBy: 1), 0,
                           "tile boundary must land on a pixel at \(s)×")
        }
    }

    /// The fixed left axis: round values, at most six of them, inside the
    /// plotted span. The step has to adapt — a Salish spring range and a
    /// half-metre creek can't share one interval — and the labels have to be
    /// values a chart datum is actually quoted in, not raw span edges.
    func testAxisTicksAreRoundAndBounded() {
        // ~4.4 m of range: whole metres, all inside the span.
        let m = axisTicks(lo: -0.4, hi: 4.0, imperial: false)
        XCTAssertEqual(m, [0, 1, 2, 3, 4])
        XCTAssert(m.allSatisfy { $0 >= -0.4 && $0 <= 4.0 }, "a tick outside the span points at nothing")

        // A narrow station drops to the half-metre step rather than showing one label.
        XCTAssertEqual(axisTicks(lo: 0.1, hi: 1.4, imperial: false), [0.5, 1.0])

        // A big range coarsens instead of printing a wall of numbers.
        XCTAssert(axisTicks(lo: -1, hi: 12, imperial: false).count <= 6)
        XCTAssert(axisTicks(lo: -1, hi: 12, imperial: true).count <= 6,
                  "~43 ft of range in feet still fits the column")

        // Imperial reads the span in feet: 4 m is ~13.1 ft, so the ticks must
        // be foot values, not metre ones leaking through.
        let ft = axisTicks(lo: 0, hi: 4.0, imperial: true)
        XCTAssertEqual(ft.last, 10, "ticks are display units — 10 ft, not 4")
        XCTAssertEqual(axisTickMetres(10, imperial: true), 10 / 3.28084, accuracy: 1e-9)
        XCTAssertEqual(axisTickMetres(3, imperial: false), 3, "metric ticks are already metres")

        // Degenerate spans can't loop forever or emit junk.
        XCTAssert(axisTicks(lo: 2, hi: 2, imperial: false).isEmpty)

        XCTAssertEqual(axisTickLabel(4), "4", "no trailing zeros in an axis column")
        XCTAssertEqual(axisTickLabel(0.5), "0.5")
        XCTAssertEqual(axisTickLabel(-0.0), "0", "no negative zero at chart datum")
    }

    /// Events scanned from a sampled series (online gates draw fetched points,
    /// not a harmonic engine): slacks at interpolated zero crossings, one signed
    /// maximum per run between them.
    func testSampleEventsScanCrossingsAndExtrema() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        // 2 → -2 → 2 over 3 h at 15-min samples: crossings at +1h and +2h... use
        // a triangle wave: v(i) = [2,1,0.5,-0.5,-1,-2,-1,-0.5,0.5,1,2] per 15 min.
        let vs: [Double] = [2, 1, 0.5, -0.5, -1, -2, -1, -0.5, 0.5, 1, 2]
        let pts = vs.enumerated().map { CurrentPoint(time: t0.addingTimeInterval(Double($0.offset) * 900), speed: $0.element) }
        let events = sampleEvents(pts)
        let slacks = events.filter { $0.kind == .slack }
        XCTAssertEqual(slacks.count, 2)
        // First crossing: between samples 2 (0.5) and 3 (-0.5) → halfway, 2250 s.
        XCTAssertEqual(slacks[0].time.timeIntervalSince(t0), 2250, accuracy: 1)
        XCTAssertEqual(slacks[1].time.timeIntervalSince(t0), 6750, accuracy: 1)
        let ebbs = events.filter { $0.kind == .maxEbb }
        XCTAssertEqual(ebbs.count, 1)
        XCTAssertEqual(ebbs[0].speed, -2, accuracy: 1e-9)
        XCTAssertEqual(ebbs[0].time.timeIntervalSince(t0), 5 * 900, accuracy: 1)
        // Leading/trailing runs also get their maxima (floods at each end).
        let floods = events.filter { $0.kind == .maxFlood }
        XCTAssertEqual(floods.count, 2)
        XCTAssertEqual(floods[0].speed, 2, accuracy: 1e-9)
        XCTAssertEqual(floods[0].time.timeIntervalSince(t0), 0, accuracy: 1)
        XCTAssertEqual(floods[1].speed, 2, accuracy: 1e-9)
        XCTAssertEqual(floods[1].time.timeIntervalSince(t0), 10 * 900, accuracy: 1)
        // Events alternate: no two slacks adjacent, no two maxima adjacent.
        for (a, b) in zip(events, events.dropFirst()) {
            XCTAssert((a.kind == .slack) != (b.kind == .slack))
        }
    }

    /// A monotone window with no crossing: one maximum, no slacks, no crash.
    func testSampleEventsMonotone() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let pts = (0..<8).map { CurrentPoint(time: t0.addingTimeInterval(Double($0) * 900), speed: 1 + Double($0) * 0.1) }
        let events = sampleEvents(pts)
        XCTAssert(events.filter { $0.kind == .slack }.isEmpty)
        XCTAssertEqual(events.filter { $0.kind == .maxFlood }.count, 1)
    }

    // MARK: - The speed ramp's absolute domain (#97)

    func testRampTLandsTheAnchorsWhereTheyBelong() {
        XCTAssertEqual(Timeline.rampT(forSpeedKn: 0.5), 0, accuracy: 1e-9)
        XCTAssertEqual(Timeline.rampT(forSpeedKn: 3), 1.0 / 3, accuracy: 1e-9)
        XCTAssertLessThan(Timeline.rampT(forSpeedKn: 2.2), 0.25,
                          "an ordinary 2.2-kn current remains in yellow")
        XCTAssertEqual(Timeline.rampT(forSpeedKn: 8), 2.0 / 3, accuracy: 1e-9)
        XCTAssertEqual(Timeline.rampT(forSpeedKn: 12), 1, accuracy: 1e-9)
        // Clamped both ends. Above the ceiling everything is the top colour;
        // "beyond the top of the scale" is not a distinction worth resolving.
        XCTAssertEqual(Timeline.rampT(forSpeedKn: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(Timeline.rampT(forSpeedKn: 40), 1, accuracy: 1e-9)
        XCTAssertEqual(Timeline.speedRampAnchorsKn.first, 0.5)
    }

    /// Ordinary currents should remain in the yellow portion of the global
    /// scale; a station-local scale would incorrectly turn them red.
    func testRampTSpreadsOrdinaryGatesAcrossTheRamp() {
        let median = Timeline.rampT(forSpeedKn: 2.26)
        XCTAssertGreaterThan(median, 0.18, "the median station must clear the ramp's floor")
        XCTAssertLessThan(median, 0.30)
        XCTAssertLessThan(Timeline.rampT(forSpeedKn: 5.0), 0.5,
                          "a 5-kn current remains below orange on the global scale")
    }

    /// **The defect this exists to fix.** `TimelineGeo` normalizes every curve
    /// to its own extremes, so a 3 kn pass and Sechelt Rapids draw the same
    /// shape. Colour is the absolutely-scaled channel now, and this is the
    /// assertion that goes red if auto-fitting is ever reintroduced into it.
    func testTwoGatesOfDifferentSpeedCannotFillTheSameColour() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        func series(peak: Double) -> [CurrentPoint] {
            (0..<75).map { i in
                let dt = Double(i) * 600
                return CurrentPoint(time: t0.addingTimeInterval(dt),
                                    speed: peak * sin(2 * .pi * dt / (12.42 * 3600)))
            }
        }
        let x: (Date) -> CGFloat = { CGFloat($0.timeIntervalSince(t0) / 3600) * Timeline.pph }
        let width = x(t0.addingTimeInterval(74 * 600))

        let mild = currentFillStops(series(peak: 3), x: x, width: width)
        let gate = currentFillStops(series(peak: 16), x: x, width: width)
        XCTAssertEqual(mild.count, 75, "one stop per sample")
        XCTAssertEqual(gate.count, 75)

        XCTAssertNotEqual(hottest(mild), hottest(gate),
                          "a 3 kn pass and a 16 kn gate must not fill the same colour")
        XCTAssertLessThan(sum(hottest(gate)), sum(hottest(mild)),
                          "the faster gate must reach the red end of the ramp")

        // CGGradient requires non-decreasing locations inside 0...1.
        XCTAssertEqual(gate.map(\.location), gate.map(\.location).sorted())
        XCTAssertTrue(gate.allSatisfy { $0.location >= 0 && $0.location <= 1 })

        XCTAssertTrue(currentFillStops([], x: x, width: width).isEmpty,
                      "no samples, no fill — an empty gradient is a crash")
        XCTAssertEqual(currentFillStops(series(peak: 3), x: x, width: 0).count, 0,
                       "a zero-width strip has no gradient to build")
    }

    /// A derived gate's curve is a schematic ±1 shape standing in for "flood,
    /// then ebb" — nobody measured a speed. Running it through the absolute
    /// ramp would draw a one-knot gate, which is the same fiction the slack
    /// windows already refuse to make out of that shape. It fills `SN.steel`,
    /// the app's existing word for a state it does not know.
    func testASchematicGateIsNotGivenASpeedItNeverHad() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let shape = (0..<75).map { i -> CurrentPoint in
            let dt = Double(i) * 600
            return CurrentPoint(time: t0.addingTimeInterval(dt),
                                speed: sin(2 * .pi * dt / (12.42 * 3600)))
        }
        let x: (Date) -> CGFloat = { CGFloat($0.timeIntervalSince(t0) / 3600) * Timeline.pph }
        let width = x(t0.addingTimeInterval(74 * 600))
        let stops = currentFillStops(shape, x: x, width: width, schematic: true)

        XCTAssertEqual(Set(stops.map(rgba)).count, 1, "a shape has one colour, not a gradient")
        XCTAssertEqual(rgba(stops[0]), rgba(Gradient.Stop(color: SN.steel.opacity(0.32), location: 0)),
                       "the unknown-magnitude fill is steel")

        // And the ramp is genuinely off: this nominal one-knot shape would
        // otherwise be yellow, not the unknown-magnitude steel.
        let ramped = currentFillStops(shape, x: x, width: width)
        XCTAssertNotEqual(rgba(stops[0]), rgba(ramped[0]))
    }

    /// The yellow → orange → red ramp gets darker as it heats up, so its
    /// darkest stop is the highest-speed one.
    private func hottest(_ stops: [Gradient.Stop]) -> [CGFloat] {
        stops.map(rgba).min { sum($0) < sum($1) } ?? []
    }

    private func sum(_ c: [CGFloat]) -> CGFloat { c.prefix(3).reduce(0, +) }

    private func rgba(_ stop: Gradient.Stop) -> [CGFloat] {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(stop.color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return [r, g, b, a].map { ($0 * 1000).rounded() / 1000 }
    }

    /// An exact-zero sample IS the slack — both polarities, no interpolation.
    func testSampleEventsExactZeroSample() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        func pts(_ vs: [Double]) -> [CurrentPoint] {
            vs.enumerated().map { CurrentPoint(time: t0.addingTimeInterval(Double($0.offset) * 900), speed: $0.element) }
        }
        for vs in [[-2.0, -1, 0, 1], [2.0, 1, 0, -1]] {
            let events = sampleEvents(pts(vs))
            let slacks = events.filter { $0.kind == .slack }
            XCTAssertEqual(slacks.count, 1, "\(vs): the zero sample is one slack")
            XCTAssertEqual(slacks[0].time.timeIntervalSince(t0), 2 * 900, accuracy: 1)
            XCTAssertEqual(events.filter { $0.kind == .maxEbb }.count, 1, "\(vs)")
            XCTAssertEqual(events.filter { $0.kind == .maxFlood }.count, 1, "\(vs)")
        }
        // Consecutive zeros: one slack, at the first zero sample.
        let events = sampleEvents(pts([1, 0, 0, -1]))
        XCTAssertEqual(events.filter { $0.kind == .slack }.count, 1)
        XCTAssertEqual(events.filter { $0.kind == .slack }[0].time.timeIntervalSince(t0), 900, accuracy: 1)
    }

    /// The online-gate path: build directly from fetched points (no engine
    /// station involved) — current-only strip, standard 340pt geometry, and
    /// every in-window event lands as a snap stop (mirrors the DerivedGateTests
    /// snap assertion for the schematic-gate path).
    func testBuildFromOnlinePointsIsCurrentOnlyAndSnaps() {
        let now = Date()
        let tz = TimeZone(identifier: "America/Vancouver")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let today = cal.startOfDay(for: now)
        // The shared definition, not a second derivation of it.
        let (start, end) = Timeline.window(anchor: today)

        // 15-min samples spanning the whole strip window, oscillating with a
        // ~12h period so slack/max events recur across it (real semidiurnal shape).
        var pts: [CurrentPoint] = []
        var t = start
        while t <= end {
            let hours = t.timeIntervalSince(start) / 3600
            pts.append(CurrentPoint(time: t, speed: 2.0 * sin(hours / 6.0 * .pi)))
            t = t.addingTimeInterval(900)
        }

        let d = TimelineData.build(onlinePoints: pts, tz: tz, lat: 48.5, lon: -123.0, now: now, anchor: today)

        // TimelineGeo keys only on which point arrays are non-empty
        // (testSingleTrackGeometries), so this is already the current-only
        // geometry — the `== 312` that used to follow just restated its height.
        XCTAssert(d.hasCurrent && !d.hasTide)
        XCTAssertFalse(d.currentEvents.isEmpty)
        // Fetched official samples are real velocities, so the online-gate path
        // gets slack windows — the derived-gate path does not, because its curve
        // is a schematic shape (gutter spec §3).
        XCTAssertFalse(d.slackWindows.isEmpty,
                       "online gates draw fetched speeds, so their slacks carry windows")
        for w in d.slackWindows {
            XCTAssert(w.start <= w.slack && w.slack <= w.end,
                      "a window must bracket its own slack: \(w)")
        }
        XCTAssert(d.currentEvents
            .filter { $0.time >= d.start && $0.time <= d.end }
            .allSatisfy { e in d.snapTimes.contains { abs($0.timeIntervalSince(e.time)) < 1 } })
    }

    /// A window ending exactly on a slack sample must not trap (the post-loop
    /// run close sees an empty run) — and the zero still reads as the slack.
    func testSampleEventsTrailingZero() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let pts = [1.0, -1, 0].enumerated().map {
            CurrentPoint(time: t0.addingTimeInterval(Double($0.offset) * 900), speed: $0.element)
        }
        let events = sampleEvents(pts)
        let slacks = events.filter { $0.kind == .slack }
        XCTAssertEqual(slacks.count, 2)                       // the crossing + the trailing zero
        XCTAssertEqual(slacks[0].time.timeIntervalSince(t0), 450, accuracy: 1)
        XCTAssertEqual(slacks[1].time.timeIntervalSince(t0), 1800, accuracy: 1)
        XCTAssertEqual(events.filter { $0.kind == .maxFlood }.count, 1)
        XCTAssertEqual(events.filter { $0.kind == .maxEbb }.count, 1)
    }

    // MARK: - The range bar label (spec §5)

    /// One label, four shapes it has to take. Was three tests with one assert
    /// each and the same two setup lines.
    func testWeekRangeLabel() {
        let tz = TimeZone(identifier: "America/Vancouver")!
        let cases: [(y: Int, m: Int, d: Int, expected: String, why: String)] = [
            // Anchor Aug 11 → groups Aug 11…Aug 17. The label names Aug 17, the
            // last day ON SCREEN, never the exclusive Aug 18 boundary.
            (2026, 8, 11, "Aug 11 – 17", "names the last day shown"),
            (2026, 8, 28, "Aug 28 – Sep 3", "spells the month when it changes"),
            (2026, 12, 29, "Dec 29 – Jan 4, 2027", "shows the year when it changes"),
            (2026, 6, 1, "Jun 1 – 7", "a same-year range never prints a year"),
        ]
        for c in cases {
            XCTAssertEqual(weekRangeLabel(anchor: vancouverMidnight(c.y, c.m, c.d), tz: tz),
                           c.expected, c.why)
        }
    }
}
