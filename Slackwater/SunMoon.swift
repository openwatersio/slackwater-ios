// Slackwater — GPL v3. Sun/moon calculator: a Swift port of the exact subset
// of suncalc 2.0.1 (BSD-2, © Vladimir Agafonkin) that slackwater-web uses plus
// what the scrubber design needs — sunrise/sunset (getTimes' -0.833° pair) and
// moon illumination/phase (Meeus ch. 48 low-precision phase angle; consumers
// only need ~1e-2 so the full term tables were cut).
// Parity-tested against the web's own suncalc outputs in SunMoonTests.
import Foundation

enum SunMoon {
    // MARK: - Julian-day plumbing (suncalc index.js)

    private static let rad = Double.pi / 180
    private static let dayMs = 1000.0 * 60 * 60 * 24
    private static let J1970 = 2440588.0
    private static let J2000 = 2451545.0

    /// JS Math.round: half rounds toward +infinity.
    private static func jsRound(_ x: Double) -> Double { (x + 0.5).rounded(.down) }

    private static func fromJulian(_ j: Double) -> Date {
        Date(timeIntervalSince1970: (j + 0.5 - J1970) * 86_400)
    }
    private static func toDays(_ date: Date) -> Double {
        date.timeIntervalSince1970 * 1000 / dayMs - 0.5 + J1970 - J2000
    }

    /// ΔT (TT − UT), seconds.
    // ponytail: constant — fine for present-day dates; restore the Espenak/Meeus
    // piecewise polynomial if historic dates are ever needed.
    private static let deltaT = 69.0
    private static func toDaysTT(_ d: Double) -> Double { d + deltaT / 86_400 }

    private static func altitude(_ H: Double, _ phi: Double, _ dec: Double) -> Double {
        asin(sin(phi) * sin(dec) + cos(phi) * cos(dec) * cos(H))
    }
    private static func siderealTime(_ d: Double, _ lw: Double) -> Double {
        rad * (280.46061837 + 360.98564736629 * d) - lw
    }

    // MARK: - Sun position (suncalc sunCoords)

    private struct EqCoords { let ra: Double; let dec: Double }

    private static func sunCoords(_ d: Double) -> EqCoords {
        let t = d / 36525
        let L0 = rad * (280.46646 + t * (36000.76983 + t * 3032e-7))
        let M = rad * (357.52911 + t * (35999.05029 - t * 1537e-7))
        let sinM = sin(M), cosM = cos(M)
        let C = rad * ((1.914602 - t * (0.004817 + t * 14e-6)) * sinM
                       + (0.019993 - 101e-6 * t) * 2 * sinM * cosM
                       + 289e-6 * sinM * (3 - 4 * sinM * sinM))
        let Om = rad * (125.04 - 1934.136 * t)
        let L = L0 + C - rad * (0.00569 + 0.00478 * sin(Om))
        let e = rad * (23.439291 - t * (0.0130042 + t * (16e-8 - t * 504e-9))) + rad * 0.00256 * cos(Om)
        return EqCoords(ra: atan2(cos(e) * sin(L), cos(L)), dec: asin(sin(e) * sin(L)))
    }

    // MARK: - Sunrise / sunset (suncalc getTimes, the -0.833° pair only)

    private static func wrapPi(_ a: Double) -> Double { a - 2 * .pi * jsRound(a / (2 * .pi)) }

    private static func solarTransit(_ dt0: Double, _ lw: Double) -> Double {
        var dt = dt0
        for _ in 0..<3 {
            let H = wrapPi(siderealTime(dt, lw) - sunCoords(toDaysTT(dt)).ra)
            dt -= H / (2 * .pi)
        }
        return dt
    }

    private static func getSetJ(_ h0: Double, _ dt: Double, _ sign: Double,
                                _ lw: Double, _ phi: Double, _ decT: Double) -> Double? {
        let cosH0 = (sin(h0) - sin(phi) * sin(decT)) / (cos(phi) * cos(decT))
        if cosH0 < -1 || cosH0 > 1 { return nil }
        var d = dt + sign * acos(cosH0) / (2 * .pi)
        for _ in 0..<2 {
            let c = sunCoords(toDaysTT(d))
            let H = wrapPi(siderealTime(d, lw) - c.ra)
            let h = altitude(H, phi, c.dec)
            let sinH = cos(phi) * cos(c.dec) * sin(H)
            if abs(sinH) < 1e-6 { break }
            d += (h - h0) / (2 * .pi * sinH)
        }
        return d
    }

    /// suncalc getTimes(date, lat, lng).sunrise/.sunset. nil = polar day/night
    /// (never for the bundled Salish stations, handled anyway like the web).
    static func sunTimes(date: Date, lat: Double, lon: Double) -> (sunrise: Date?, sunset: Date?) {
        let lw = rad * -lon
        let phi = rad * lat
        let J0 = 9e-4
        let dt = solarTransit(jsRound(jsRound(toDays(date)) - J0 - lw / (2 * .pi)) + J0 + lw / (2 * .pi), lw)
        let dec = sunCoords(toDaysTT(dt)).dec
        let h0 = -0.833 * rad
        let jrise = getSetJ(h0, dt, -1, lw, phi, dec)
        let jset = getSetJ(h0, dt, 1, lw, phi, dec)
        return (jrise.map { fromJulian($0 + J2000) }, jset.map { fromJulian($0 + J2000) })
    }

    // MARK: - Day events (web tides.ts sunEventsFor: widen ±1 day, keep the local day)

    enum SunEventKind { case sunrise, sunset }
    struct SunEvent { let time: Date; let kind: SunEventKind }

    static func sunEvents(lat: Double, lon: Double, tz: TimeZone, day: Date) -> [SunEvent] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let start = cal.startOfDay(for: day)
        let end = start.addingTimeInterval(86_400)
        var events: [SunEvent] = []
        for offset in [-1.0, 0, 1] {
            let t = sunTimes(date: day.addingTimeInterval(offset * 86_400), lat: lat, lon: lon)
            if let rise = t.sunrise, rise >= start, rise < end { events.append(SunEvent(time: rise, kind: .sunrise)) }
            if let set = t.sunset, set >= start, set < end { events.append(SunEvent(time: set, kind: .sunset)) }
        }
        return events.sorted { $0.time < $1.time }
    }

    // MARK: - Moon illumination (Meeus ch. 48 low-precision phase angle)

    struct MoonIllumination {
        /// Illuminated fraction 0…1.
        let fraction: Double
        /// Phase 0…1: 0 new, 0.25 first quarter, 0.5 full, 0.75 last quarter.
        let phase: Double
        let waxing: Bool
    }

    // ponytail: Meeus ch. 48 eq. 48.4 — good to ~2e-3 in fraction; the glyph,
    // glow, and phase-name buckets need ~1e-2. Restore the suncalc/Meeus full
    // term tables (git history) if anything ever needs 1e-6 parity again.
    static func moonIllumination(date: Date) -> MoonIllumination {
        let t = toDaysTT(toDays(date)) / 36525
        let D = rad * (297.8501921 + 445267.1114034 * t)   // mean elongation
        let M = rad * (357.5291092 + 35999.0502909 * t)    // sun mean anomaly
        let Mp = rad * (134.9633964 + 477198.8675055 * t)  // moon mean anomaly
        let iRaw = Double.pi - D - rad * (6.289 * sin(Mp) - 2.100 * sin(M)
            + 1.274 * sin(2 * D - Mp) + 0.658 * sin(2 * D)
            + 0.214 * sin(2 * Mp) + 0.110 * sin(D))
        let signed = wrapPi(iRaw)   // phase angle, sign carries waxing/waning
        let inc = abs(signed)
        let waxing = signed > 0
        return MoonIllumination(fraction: (1 + cos(inc)) / 2,
                                phase: 0.5 + 0.5 * inc * (waxing ? -1 : 1) / .pi,
                                waxing: waxing)
    }

    /// Phase → name, the prototype's moonName buckets (age thresholds 1.7 d for
    /// new/full, 1.4 d for the quarters, over the 29.53 d synodic month).
    static func phaseName(phase: Double) -> String {
        let syn = 29.53
        let age = phase * syn
        let waxing = age < syn / 2
        if age < 1.7 || age > syn - 1.7 { return "New Moon" }
        if abs(age - syn / 2) < 1.7 { return "Full Moon" }
        if abs(age - syn / 4) < 1.4 { return "First Quarter" }
        if abs(age - 3 * syn / 4) < 1.4 { return "Last Quarter" }
        let fraction = (1 - cos(2 * .pi * age / syn)) / 2
        if fraction < 0.5 { return waxing ? "Waxing Crescent" : "Waning Crescent" }
        return waxing ? "Waxing Gibbous" : "Waning Gibbous"
    }
}
