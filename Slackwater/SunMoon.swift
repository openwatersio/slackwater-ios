// Slackwater — GPL v3. Sun/moon calculator: a Swift port of the exact subset
// of suncalc 2.0.1 (BSD-2, © Vladimir Agafonkin) that slackwater-web uses plus
// what the scrubber design needs — sunrise/sunset (getTimes' -0.833° pair) and
// moon illumination/phase (getMoonIllumination, full Meeus term tables so the
// numbers match the web's dependency, not an approximation of it).
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

    /// ΔT (TT − UT), seconds — suncalc's Espenak/Meeus piecewise fit.
    private static func deltaT(_ d: Double) -> Double {
        let y = 2000 + d / 365.2425
        var t: Double
        if y < 1920 { t = y - 1900; return -2.79 + t * (1.494119 + t * (-0.0598939 + t * (0.0061966 - t * 197e-6))) }
        if y < 1941 { t = y - 1920; return 21.2 + t * (0.84493 + t * (-0.0761 + t * 0.0020936)) }
        if y < 1961 { t = y - 1950; return 29.07 + t * (0.407 + t * (-1 / 233 + t / 2547)) }
        if y < 1986 { t = y - 1975; return 45.45 + t * (1.067 + t * (-1 / 260 - t / 718)) }
        if y < 2005 { t = y - 2000; return 63.86 + t * (0.3345 + t * (-0.060374 + t * (0.0017275 + t * (651814e-9 + t * 2373599e-11)))) }
        if y < 2050 { t = y - 2000; return 62.92 + t * (0.32217 + t * 0.005589) }
        t = (y - 1820) / 100
        return -20 + 32 * t * t - 0.5628 * (2150 - y)
    }
    private static func toDaysTT(_ d: Double) -> Double { d + deltaT(d) / 86_400 }

    private static func altitude(_ H: Double, _ phi: Double, _ dec: Double) -> Double {
        asin(sin(phi) * sin(dec) + cos(phi) * cos(dec) * cos(H))
    }
    private static func siderealTime(_ d: Double, _ lw: Double) -> Double {
        rad * (280.46061837 + 360.98564736629 * d) - lw
    }

    // MARK: - Sun position (suncalc sunCoords)

    private struct EqCoords { let ra: Double; let dec: Double; var dist: Double = 0 }

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

    // MARK: - Moon (suncalc moonCoords — full Meeus tables — + getMoonIllumination)

    private static func nutationObliquity(_ t: Double) -> (dpsi: Double, eps: Double) {
        let om = rad * (125.04452 - 1934.136261 * t)
        let ls = rad * (280.4665 + 36000.7698 * t)
        let lm = rad * (218.3165 + 481267.8813 * t)
        let dpsi = (-17.2 * sin(om) - 1.32 * sin(2 * ls) - 0.23 * sin(2 * lm) + 0.21 * sin(2 * om)) / 3600
        let deps = (9.2 * cos(om) + 0.57 * cos(2 * ls) + 0.1 * cos(2 * lm) - 0.09 * cos(2 * om)) / 3600
        return (dpsi, rad * (23.439291 - t * (0.0130042 + t * (16e-8 - t * 504e-9)) + deps))
    }

    // [D, M, Mp, F, sinCoeff(lon ×1e-6°), cosCoeff(dist ×1e-3 km)] × 60 terms
    private static let moonLon: [Double] = [
        0, 0, 1, 0, 6288774, -20905355,
        2, 0, -1, 0, 1274027, -3699111,
        2, 0, 0, 0, 658314, -2955968,
        0, 0, 2, 0, 213618, -569925,
        0, 1, 0, 0, -185116, 48888,
        0, 0, 0, 2, -114332, -3149,
        2, 0, -2, 0, 58793, 246158,
        2, -1, -1, 0, 57066, -152138,
        2, 0, 1, 0, 53322, -170733,
        2, -1, 0, 0, 45758, -204586,
        0, 1, -1, 0, -40923, -129620,
        1, 0, 0, 0, -34720, 108743,
        0, 1, 1, 0, -30383, 104755,
        2, 0, 0, -2, 15327, 10321,
        0, 0, 1, 2, -12528, 0,
        0, 0, 1, -2, 10980, 79661,
        4, 0, -1, 0, 10675, -34782,
        0, 0, 3, 0, 10034, -23210,
        4, 0, -2, 0, 8548, -21636,
        2, 1, -1, 0, -7888, 24208,
        2, 1, 0, 0, -6766, 30824,
        1, 0, -1, 0, -5163, -8379,
        1, 1, 0, 0, 4987, -16675,
        2, -1, 1, 0, 4036, -12831,
        2, 0, 2, 0, 3994, -10445,
        4, 0, 0, 0, 3861, -11650,
        2, 0, -3, 0, 3665, 14403,
        0, 1, -2, 0, -2689, -7003,
        2, 0, -1, 2, -2602, 0,
        2, -1, -2, 0, 2390, 10056,
        1, 0, 1, 0, -2348, 6322,
        2, -2, 0, 0, 2236, -9884,
        0, 1, 2, 0, -2120, 5751,
        0, 2, 0, 0, -2069, 0,
        2, -2, -1, 0, 2048, -4950,
        2, 0, 1, -2, -1773, 4130,
        2, 0, 0, 2, -1595, 0,
        4, -1, -1, 0, 1215, -3958,
        0, 0, 2, 2, -1110, 0,
        3, 0, -1, 0, -892, 3258,
        2, 1, 1, 0, -810, 2616,
        4, -1, -2, 0, 759, -1897,
        0, 2, -1, 0, -713, -2117,
        2, 2, -1, 0, -700, 2354,
        2, 1, -2, 0, 691, 0,
        2, -1, 0, -2, 596, 0,
        4, 0, 1, 0, 549, -1423,
        0, 0, 4, 0, 537, -1117,
        4, -1, 0, 0, 520, -1571,
        1, 0, -2, 0, -487, -1739,
        2, 1, 0, -2, -399, 0,
        0, 0, 2, -2, -381, -4421,
        1, 1, 1, 0, 351, 0,
        3, 0, -2, 0, -340, 0,
        4, 0, -3, 0, 330, 0,
        2, -1, 2, 0, 327, 0,
        0, 2, 1, 0, -323, 1165,
        1, 1, -1, 0, 299, 0,
        2, 0, 3, 0, 294, 0,
        2, 0, -1, -2, 0, 8752,
    ]

    // [D, M, Mp, F, sinCoeff(lat ×1e-6°)] × 60 terms
    private static let moonLat: [Double] = [
        0, 0, 0, 1, 5128122,
        0, 0, 1, 1, 280602,
        0, 0, 1, -1, 277693,
        2, 0, 0, -1, 173237,
        2, 0, -1, 1, 55413,
        2, 0, -1, -1, 46271,
        2, 0, 0, 1, 32573,
        0, 0, 2, 1, 17198,
        2, 0, 1, -1, 9266,
        0, 0, 2, -1, 8822,
        2, -1, 0, -1, 8216,
        2, 0, -2, -1, 4324,
        2, 0, 1, 1, 4200,
        2, 1, 0, -1, -3359,
        2, -1, -1, 1, 2463,
        2, -1, 0, 1, 2211,
        2, -1, -1, -1, 2065,
        0, 1, -1, -1, -1870,
        4, 0, -1, -1, 1828,
        0, 1, 0, 1, -1794,
        0, 0, 0, 3, -1749,
        0, 1, -1, 1, -1565,
        1, 0, 0, 1, -1491,
        0, 1, 1, 1, -1475,
        0, 1, 1, -1, -1410,
        0, 1, 0, -1, -1344,
        1, 0, 0, -1, -1335,
        0, 0, 3, 1, 1107,
        4, 0, 0, -1, 1021,
        4, 0, -1, 1, 833,
        0, 0, 1, -3, 777,
        4, 0, -2, 1, 671,
        2, 0, 0, -3, 607,
        2, 0, 2, -1, 596,
        2, -1, 1, -1, 491,
        2, 0, -2, 1, -451,
        0, 0, 3, -1, 439,
        2, 0, 2, 1, 422,
        2, 0, -3, -1, 421,
        2, 1, -1, 1, -366,
        2, 1, 0, 1, -351,
        4, 0, 0, 1, 331,
        2, -1, 1, 1, 315,
        2, -2, 0, -1, 302,
        0, 0, 1, 3, -283,
        2, 1, 1, -1, -229,
        1, 1, 0, -1, 223,
        1, 1, 0, 1, 223,
        0, 1, -2, -1, -220,
        2, 1, -1, -1, -220,
        1, 0, 1, 1, -185,
        2, -1, -2, -1, 181,
        0, 1, 2, 1, -177,
        4, 0, -2, -1, 176,
        4, -1, -1, -1, 166,
        1, 0, 1, -1, -164,
        4, 0, 1, -1, 132,
        1, 0, -1, -1, -119,
        4, -1, 0, -1, 115,
        2, -2, 0, 1, 107,
    ]

    private static func moonCoords(_ d: Double) -> EqCoords {
        let t = d / 36525
        let Lp = 218.3164477 + t * (481267.88123421 + t * (-0.0015786 + t * (1 / 538841 - t / 65194e3)))
        let D = 297.8501921 + t * (445267.1114034 + t * (-0.0018819 + t * (1 / 545868 - t / 113065e3)))
        let M = 357.5291092 + t * (35999.0502909 + t * (-1536e-7 + t / 2449e4))
        let Mp = 134.9633964 + t * (477198.8675055 + t * (0.0087414 + t * (1 / 69699 - t / 14712e3)))
        let F = 93.272095 + t * (483202.0175233 + t * (-0.0036539 + t * (-1 / 3526e3 + t / 86331e4)))
        let A1 = 119.75 + 131.849 * t
        let A2 = 53.09 + 479264.29 * t
        let A3 = 313.45 + 481266.484 * t
        let E = 1 - t * (0.002516 + t * 74e-7)
        let Dr = rad * D, Mr = rad * M, Mpr = rad * Mp, Fr = rad * F
        var sl = 0.0, sr = 0.0, sb = 0.0
        var i = 0
        while i < moonLon.count {
            let m = moonLon[i + 1]
            let arg = moonLon[i] * Dr + m * Mr + moonLon[i + 2] * Mpr + moonLon[i + 3] * Fr
            let f = (m == 1 || m == -1) ? E : (m == 2 || m == -2) ? E * E : 1
            sl += moonLon[i + 4] * f * sin(arg)
            sr += moonLon[i + 5] * f * cos(arg)
            i += 6
        }
        i = 0
        while i < moonLat.count {
            let m = moonLat[i + 1]
            let arg = moonLat[i] * Dr + m * Mr + moonLat[i + 2] * Mpr + moonLat[i + 3] * Fr
            let f = (m == 1 || m == -1) ? E : (m == 2 || m == -2) ? E * E : 1
            sb += moonLat[i + 4] * f * sin(arg)
            i += 5
        }
        let A1r = rad * A1, Lpr = rad * Lp
        sl += 3958 * sin(A1r) + 1962 * sin(Lpr - Fr) + 318 * sin(rad * A2)
        sb += -2235 * sin(Lpr) + 382 * sin(rad * A3) + 175 * sin(A1r - Fr)
            + 175 * sin(A1r + Fr) + 127 * sin(Lpr - Mpr) - 115 * sin(Lpr + Mpr)
        let (dpsi, eps) = nutationObliquity(t)
        let l = rad * (Lp + sl / 1e6 + dpsi)
        let b = rad * (sb / 1e6)
        return EqCoords(ra: atan2(sin(l) * cos(eps) - tan(b) * sin(eps), cos(l)),
                        dec: asin(sin(b) * cos(eps) + cos(b) * sin(eps) * sin(l)),
                        dist: 385000.56 + sr / 1e3)
    }

    struct MoonIllumination {
        /// Illuminated fraction 0…1.
        let fraction: Double
        /// Phase 0…1: 0 new, 0.25 first quarter, 0.5 full, 0.75 last quarter.
        let phase: Double
        let waxing: Bool
    }

    static func moonIllumination(date: Date) -> MoonIllumination {
        let d = toDaysTT(toDays(date))
        let s = sunCoords(d)
        let m = moonCoords(d)
        let sdist = 149598e3
        let phi = acos(sin(s.dec) * sin(m.dec) + cos(s.dec) * cos(m.dec) * cos(s.ra - m.ra))
        let inc = atan2(sdist * sin(phi), m.dist - sdist * cos(phi))
        let angle = atan2(cos(s.dec) * sin(s.ra - m.ra),
                          sin(s.dec) * cos(m.dec) - cos(s.dec) * sin(m.dec) * cos(s.ra - m.ra))
        let waxing = angle < 0
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
