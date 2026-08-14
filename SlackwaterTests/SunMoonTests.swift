// Slackwater — GPL v3. Parity tests for the SunMoon port against the web's
// own dependency (suncalc 2.0.1, the exact build slackwater-web ships).
// Fixtures generated with node from slackwater-web/node_modules/suncalc:
//   SunCalc.getTimes(date, lat, lon).sunrise/.sunset (ISO, ms precision)
//   SunCalc.getMoonIllumination(date).fraction/.phase
// 3 stations × 3 dates; sun times must agree to the minute, moon fraction and
// phase to 1e-2 (SunMoon uses the Meeus ch. 48 low-precision phase angle).
import XCTest
@testable import Slackwater

final class SunMoonTests: XCTestCase {
    struct Fixture {
        let station: String
        let lat: Double, lon: Double
        let date: String       // input instant, ISO8601
        let sunrise: String    // suncalc output, ISO8601 UTC
        let sunset: String
        let fraction: Double
        let phase: Double
    }

    // friday = Friday Harbor (noaa/9449880), victoria = chs-victoria,
    // owenbay = chs-owen-bay (northernmost bundled station).
    let fixtures: [Fixture] = [
        .init(station: "friday", lat: 48.54527777777778, lon: -123.0125,
              date: "2026-07-30T19:00:00Z",
              sunrise: "2026-07-30T12:44:09.233Z", sunset: "2026-07-31T03:52:01.892Z",
              fraction: 0.98637, phase: 0.53725),
        .init(station: "friday", lat: 48.54527777777778, lon: -123.0125,
              date: "2026-01-15T20:00:00Z",
              sunrise: "2026-01-15T15:58:49.078Z", sunset: "2026-01-16T00:44:45.117Z",
              fraction: 0.08563, phase: 0.90547),
        .init(station: "friday", lat: 48.54527777777778, lon: -123.0125,
              date: "2026-10-31T19:00:00Z",
              sunrise: "2026-10-31T14:57:03.297Z", sunset: "2026-11-01T00:53:36.448Z",
              fraction: 0.62070, phase: 0.71120),
        .init(station: "victoria", lat: 48.424, lon: -123.371,
              date: "2026-07-30T19:00:00Z",
              sunrise: "2026-07-30T12:46:00.276Z", sunset: "2026-07-31T03:53:03.226Z",
              fraction: 0.98637, phase: 0.53725),
        .init(station: "victoria", lat: 48.424, lon: -123.371,
              date: "2026-01-15T20:00:00Z",
              sunrise: "2026-01-15T15:59:47.986Z", sunset: "2026-01-16T00:46:38.250Z",
              fraction: 0.08563, phase: 0.90547),
        .init(station: "victoria", lat: 48.424, lon: -123.371,
              date: "2026-10-31T19:00:00Z",
              sunrise: "2026-10-31T14:58:12.751Z", sunset: "2026-11-01T00:55:19.216Z",
              fraction: 0.62070, phase: 0.71120),
        .init(station: "owenbay", lat: 50.31, lon: -125.223,
              date: "2026-07-30T19:00:00Z",
              sunrise: "2026-07-30T12:46:40.761Z", sunset: "2026-07-31T04:07:06.645Z",
              fraction: 0.98637, phase: 0.53725),
        .init(station: "owenbay", lat: 50.31, lon: -125.223,
              date: "2026-01-15T20:00:00Z",
              sunrise: "2026-01-15T16:14:31.663Z", sunset: "2026-01-16T00:46:45.034Z",
              fraction: 0.08563, phase: 0.90547),
        .init(station: "owenbay", lat: 50.31, lon: -125.223,
              date: "2026-10-31T19:00:00Z",
              sunrise: "2026-10-31T15:10:07.133Z", sunset: "2026-11-01T00:58:11.442Z",
              fraction: 0.62070, phase: 0.71120),
    ]

    private func iso(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)!
    }

    func testSunTimesParity() {
        for fx in fixtures {
            let t = SunMoon.sunTimes(date: iso(fx.date), lat: fx.lat, lon: fx.lon)
            let rise = try! XCTUnwrap(t.sunrise, "\(fx.station) \(fx.date): no sunrise")
            let set = try! XCTUnwrap(t.sunset, "\(fx.station) \(fx.date): no sunset")
            XCTAssertEqual(rise.timeIntervalSince(iso(fx.sunrise)), 0, accuracy: 60,
                           "\(fx.station) \(fx.date) sunrise")
            XCTAssertEqual(set.timeIntervalSince(iso(fx.sunset)), 0, accuracy: 60,
                           "\(fx.station) \(fx.date) sunset")
        }
    }

    func testMoonIlluminationParity() {
        for fx in fixtures {
            let m = SunMoon.moonIllumination(date: iso(fx.date))
            XCTAssertEqual(m.fraction, fx.fraction, accuracy: 0.01,
                           "\(fx.station) \(fx.date) fraction")
            XCTAssertEqual(m.phase, fx.phase, accuracy: 0.01,
                           "\(fx.station) \(fx.date) phase")
        }
    }

    func testMoonPhaseNames() {
        // Prototype moonName buckets (TidesApp.dc.html), driven by phase.
        XCTAssertEqual(SunMoon.phaseName(phase: 0.001), "New Moon")
        XCTAssertEqual(SunMoon.phaseName(phase: 0.995), "New Moon")
        XCTAssertEqual(SunMoon.phaseName(phase: 0.25), "First Quarter")
        XCTAssertEqual(SunMoon.phaseName(phase: 0.5), "Full Moon")
        XCTAssertEqual(SunMoon.phaseName(phase: 0.75), "Last Quarter")
        XCTAssertEqual(SunMoon.phaseName(phase: 0.12), "Waxing Crescent")
        XCTAssertEqual(SunMoon.phaseName(phase: 0.38), "Waxing Gibbous")
        XCTAssertEqual(SunMoon.phaseName(phase: 0.62), "Waning Gibbous")
        XCTAssertEqual(SunMoon.phaseName(phase: 0.88), "Waning Crescent")
    }

    // The widen-then-filter day bucketing (web sunEventsFor): events land in
    // the station's local day even though suncalc buckets by UTC day.
    func testSunEventsForLocalDay() {
        let tz = TimeZone(identifier: "America/Los_Angeles")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        // Local-evening instant: UTC is already tomorrow — the classic clip.
        let evening = iso("2026-07-31T05:30:00Z")  // Jul 30, 10:30 PM PDT
        let events = SunMoon.sunEvents(lat: 48.545, lon: -123.0125, tz: tz, day: evening)
        XCTAssertEqual(events.count, 2)
        let dayStart = cal.startOfDay(for: evening)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!  // exact across DST, unlike +86400
        for e in events {
            XCTAssert(e.time >= dayStart && e.time < dayEnd,
                      "event \(e.time) outside the local day")
        }
        XCTAssertEqual(events[0].kind, .sunrise)
        XCTAssertEqual(events[1].kind, .sunset)
    }
}
