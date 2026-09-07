// Slackwater — GPL v3. Lunar eclipses for the strip, the schedule and the
// Moon sheet. The astronomy is Almanac's; everything here is windowing and
// presentation.
import Almanac
import Foundation

/// One eclipse paired with what this observer can see of it. Built once per
/// timeline build — never on a scrub frame — and carried on `TimelineData`.
struct WindowEclipse: Identifiable {
    let eclipse: LunarEclipse
    let visibility: LunarEclipseVisibility

    var id: Date { eclipse.peak }
    var kind: LunarEclipseKind { eclipse.kind }
    var peak: Date { eclipse.peak }

    /// The instant the shadow first bites — U1, or P1 for a penumbral eclipse,
    /// which has no umbral contact at all. What the list row and the strip
    /// mark point at, and what "scrub to the start" means.
    var start: Date { eclipse.u1 ?? eclipse.p1 }

    /// The snap targets, chronological, nils dropped: P1, U1, greatest, U4, P4.
    var contacts: [Date] {
        [eclipse.p1, eclipse.u1, eclipse.peak, eclipse.u4, eclipse.p4].compactMap { $0 }
    }

    /// Any contact with the moon above this observer's horizon. The test for
    /// whether the event is worth a row here — deliberately weaker than
    /// `visibility.visibleAtPeak`, so an eclipse already underway at moonrise
    /// still counts. That is the one worth walking outside for.
    var anyContactVisible: Bool {
        let v = visibility.contactsVisible
        return [v.p1, v.u1, v.u2, v.u3, v.u4, v.p4].contains { $0 == true }
            || visibility.visibleAtPeak
    }

    /// Anywhere in the event, first to last penumbral contact. Dims the dome's
    /// glow and renames the Moon tile.
    func underway(at t: Date) -> Bool { t >= eclipse.p1 && t <= eclipse.p4 }

    /// Fraction of the moon's diameter inside the UMBRA at `t`, 0 outside the
    /// umbral phase — including for the whole of a penumbral eclipse, which
    /// has no umbral contact. That is not a gap: a penumbral eclipse is a
    /// dimming rather than a bite, and `wash(at:)` below is what carries it.
    ///
    /// ponytail: linear between contacts. Almanac reports contact instants and
    /// the magnitude at greatest eclipse, not a coverage curve; the shape
    /// between them is this app's drawing. The endpoints and the peak are
    /// exact, the middle is within a few percent of the real chord geometry,
    /// and no number here is ever printed — it only moves a shadow. Upgrade
    /// path if one ever is printed: chord geometry from the shadow radii,
    /// which means an Almanac API for them.
    func shadow(at t: Date) -> Double {
        guard let u1 = eclipse.u1, let u4 = eclipse.u4, t >= u1, t <= u4 else { return 0 }
        let mag = max(eclipse.magUmbral, 0)
        if t <= peak {
            let span = peak.timeIntervalSince(u1)
            return span > 0 ? mag * t.timeIntervalSince(u1) / span : mag
        }
        let span = u4.timeIntervalSince(peak)
        return span > 0 ? mag * u4.timeIntervalSince(t) / span : mag
    }

    /// The PENUMBRAL shading at `t`, 0…1 — the whole disc dimming and warming
    /// rather than a bite taken out of it.
    ///
    /// This is the channel that makes a penumbral eclipse visible at all:
    /// it has no umbral contact, so `shadow(at:)` is 0 for its entire
    /// duration, and without this the moon would look untouched while the app
    /// claims an eclipse is underway. It is also what the sky really does —
    /// a penumbral eclipse IS a dimming, not a bite.
    ///
    /// Clamped at 1: `magPenumbral` runs well above 1 for a deep partial,
    /// where the umbral bite is carrying the reading anyway.
    func wash(at t: Date) -> Double {
        let p1 = eclipse.p1, p4 = eclipse.p4
        guard t >= p1, t <= p4 else { return 0 }
        let mag = min(max(eclipse.magPenumbral, 0), 1)
        if t <= peak {
            let span = peak.timeIntervalSince(p1)
            return span > 0 ? mag * t.timeIntervalSince(p1) / span : mag
        }
        let span = p4.timeIntervalSince(peak)
        return span > 0 ? mag * p4.timeIntervalSince(t) / span : mag
    }
}

/// Every eclipse in `from..<to` that this observer can see any contact of.
///
/// The search itself is Almanac's `lunarEclipses(from:to:)` (0.2.0, from
/// openwatersio/almanac#6 — this app's consumer loop is what prompted it, and
/// CI measured the native range search 65–99% faster than the loop it
/// replaced). What is left here is the visibility filter, which stays a
/// separate observer query in Almanac by design.
///
/// Named `visibleEclipses`, not `lunarEclipses`: sharing a name with the
/// Almanac function it calls would resolve fine by argument label and read
/// like a bug at every call site.
func visibleEclipses(from: Date, to: Date, observer: Observer) -> [WindowEclipse] {
    guard let found = try? lunarEclipses(from: from, to: to) else { return [] }
    return found.compactMap { visible($0, observer: observer) }
}

/// The last eclipse before `at` that can be seen from here, or nil.
///
/// Almanac walks backward natively as of 0.2.0; the loop that remains only
/// skips eclipses this observer misses, which is why it is bounded by a COUNT
/// rather than by a span of days. Eight is roughly three years of eclipses —
/// past that, "the last one you could see" is not a fact worth printing.
func previousVisibleEclipse(before at: Date, observer: Observer) -> WindowEclipse? {
    var cursor = at
    for _ in 0..<8 {
        guard let e = try? previousLunarEclipse(before: cursor) else { return nil }
        cursor = e.peak
        if let found = visible(e, observer: observer) { return found }
    }
    return nil
}

/// The next eclipse after `at` that can be seen from here, or nil. The mirror
/// of `previousVisibleEclipse`, same bound, same reason.
func nextVisibleEclipse(after at: Date, observer: Observer) -> WindowEclipse? {
    var cursor = at
    for _ in 0..<8 {
        guard let e = try? nextLunarEclipse(after: cursor) else { return nil }
        cursor = e.peak
        if let found = visible(e, observer: observer) { return found }
    }
    return nil
}

private func visible(_ e: LunarEclipse, observer: Observer) -> WindowEclipse? {
    guard let v = try? lunarEclipseVisibility(e, observer: observer) else { return nil }
    let windowed = WindowEclipse(eclipse: e, visibility: v)
    return windowed.anyContactVisible ? windowed : nil
}
