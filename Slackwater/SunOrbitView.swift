import Almanac
import SwiftUI

struct SunOrbitFacts: Sendable {
    let at: Date
    let distanceKm: Double
    let perihelion: EarthApsis
    let aphelion: EarthApsis
    let angle: Double

    init(at: Date) throws {
        self.at = at
        let position = try sunPosition(at)
        distanceKm = position.distanceAu * 149_597_870.7
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let year = calendar.component(.year, from: at)
        let from = calendar.date(from: DateComponents(year: max(1950, year - 1), month: 1, day: 1))!
        let to = calendar.date(from: DateComponents(year: min(2101, year + 2), month: 1, day: 1))!
        let events = try earthApsides(from: from, to: to)
        let nearest = events.sorted { abs($0.time.timeIntervalSince(at)) < abs($1.time.timeIntervalSince(at)) }
        guard let near = nearest.first(where: { $0.kind == .perihelion }),
              let far = nearest.first(where: { $0.kind == .aphelion }) else {
            throw AlmanacError.invalidArgument("Missing Earth apsides")
        }
        perihelion = near
        aphelion = far
        let before = events.last(where: { $0.time <= at }) ?? events[0]
        let after = events.first(where: { $0.time > before.time }) ?? events[events.count - 1]
        let start = before.time == after.time ? events[events.count - 2] : before
        // Interpolate between Almanac's extrema on the schematic, so each date lands on its marker.
        let fraction = at.timeIntervalSince(start.time) / after.time.timeIntervalSince(start.time)
        angle = (start.kind == .perihelion ? 0 : .pi) + fraction * .pi
    }
}

struct SunDistanceView: View {
    let facts: SunOrbitFacts
    let tz: TimeZone
    let onJump: (Date) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption2) private var labelSpace = 80

    var body: some View {
        VStack(spacing: 0) {
            let headerLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout())
            headerLayout {
                MonoLabel(text: String(localized: "Distance from Earth"), color: SN.foam.opacity(0.55))
                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                Text(verbatim: distance(facts.distanceKm))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(SN.foam)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .accessibilityElement(children: .combine)
            GeometryReader { geometry in orbit(width: geometry.size.width) }
                .frame(height: dynamicTypeSize.isAccessibilitySize ? 140 : 140 + labelSpace)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 14) {
                    eventLink(facts.aphelion, label: String(localized: "Aphelion"))
                    eventLink(facts.perihelion, label: String(localized: "Perihelion"))
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
            Text("Orbit exaggerated for clarity.")
                .font(.caption2)
                .foregroundStyle(SN.foam.opacity(0.5))
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
        }
        .background(SN.cardFill, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(SN.cardStroke, lineWidth: 0.5))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sun-distance")
    }

    private func orbit(width: CGFloat) -> some View {
        // Schematic eccentricity matches the Moon diagram; all printed values remain exact.
        let e = 0.35
        let squash = 0.42
        let a = min(max((width - 116) / 2, 30), 140)
        let b = a * sqrt(1 - e * e)
        let cy = 16 + b * squash
        let focus = CGPoint(x: width / 2 + a * e, y: cy)
        let place = { (p: CGPoint) in CGPoint(x: focus.x + p.x, y: focus.y + p.y * squash) }
        let near = place(orbitPoint(trueAnomaly: 0, a: a, e: e))
        let far = place(orbitPoint(trueAnomaly: .pi, a: a, e: e))
        let earth = place(orbitPoint(trueAnomaly: facts.angle, a: a, e: e))
        let floor = cy + b * squash
        return ZStack {
            Path { path in
                for step in 0...180 {
                    let point = place(orbitPoint(trueAnomaly: Double(step) * .pi / 90, a: a, e: e))
                    if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                path.closeSubpath()
            }
            .stroke(SN.foam.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
            .accessibilityHidden(true)
            Path { path in
                path.move(to: focus)
                path.addLine(to: earth)
            }
            .stroke(SN.steel.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [1, 3]))
            .accessibilityHidden(true)
            Circle().fill(SN.sun).frame(width: 18, height: 18)
                .shadow(color: SN.sun.opacity(0.4), radius: 8)
                .position(focus)
                .accessibilityHidden(true)
            Circle().fill(SN.flood).frame(width: 13, height: 13)
                .overlay(Circle().strokeBorder(SN.foam.opacity(0.3), lineWidth: 0.75))
                .position(earth)
                .accessibilityHidden(true)
            vertex(facts.perihelion, label: String(localized: "Perihelion"), at: near, floor: floor)
            vertex(facts.aphelion, label: String(localized: "Aphelion"), at: far, floor: floor)
        }
    }

    private func vertex(_ event: EarthApsis, label: String, at point: CGPoint, floor: CGFloat) -> some View {
        ZStack {
            Circle().fill(SN.foam.opacity(0.75)).frame(width: 5, height: 5)
                .position(point)
                .accessibilityHidden(true)
            if !dynamicTypeSize.isAccessibilitySize {
                eventLink(event, label: label)
                    .frame(width: 112).frame(minHeight: 58)
                    .position(x: point.x, y: floor + labelSpace / 2)
            }
        }
    }

    private func eventLink(_ event: EarthApsis, label: String) -> some View {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        let sameYear = calendar.component(.year, from: event.time) == calendar.component(.year, from: facts.at)
        let date = sameYear ? monthDay(event.time, tz) : monthDayYear(event.time, tz)
        return Button { onJump(event.time) } label: {
            VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .center, spacing: 3) {
                Text(label).font(.caption2).foregroundStyle(SN.foam.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                Text(date).font(.caption2.monospacedDigit()).foregroundStyle(SN.foam)
                Text(verbatim: distance(event.distanceKm))
                    .font(dynamicTypeSize.isAccessibilitySize
                          ? .caption2.monospacedDigit() : .system(size: 10).monospacedDigit())
                    .foregroundStyle(SN.foam.opacity(0.55))
            }
            .frame(maxWidth: .infinity, alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .center)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(chartTime(event.time, tz))
        .accessibilityIdentifier(event.kind == .perihelion ? "sun-perihelion" : "sun-aphelion")
    }

    private func distance(_ km: Double) -> String {
        "\((Int((km / 10_000).rounded()) * 10_000).formatted(.number)) km"
    }
}
