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

/// Every lunar eclipse whose peak falls in `from...to` and that this observer
/// can see any contact of.
///
/// Walks `nextLunarEclipse(after:)` forward — Almanac has no range or backward
/// search (openwatersio/almanac#6). Almanac throws outside 1950–2101; that
/// ends the walk and returns what was found, the way `SummaryTiles` drops its
/// tile rather than the row.
func lunarEclipses(from: Date, to: Date, observer: Observer) -> [WindowEclipse] {
    var out: [WindowEclipse] = []
    var cursor = from
    while cursor < to {
        guard let e = try? nextLunarEclipse(after: cursor), e.peak <= to else { break }
        cursor = e.peak
        guard let v = try? lunarEclipseVisibility(e, observer: observer) else { continue }
        let windowed = WindowEclipse(eclipse: e, visibility: v)
        if windowed.anyContactVisible { out.append(windowed) }
    }
    return out
}
