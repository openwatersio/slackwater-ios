// Slackwater — GPL v3. The month's free day on the Premium sheet: offered, running, or used.
import SwiftUI

struct FreeDayButton: View {
    @ObservedObject private var freeDay = FreeDayStore.shared
    // Observed for its end-of-day update, which turns "until" into "next".
    @ObservedObject private var premium = PremiumStore.shared

    var body: some View {
        if !premium.hasPurchased {
            let now = appNow()
            Group {
                if let day = freeDay.current, freeDayRunning(day, at: now) {
                    Text("Free day until \(Text(day.end, style: .time))")
                        .foregroundStyle(SN.leaf)
                } else if freeDayAvailable(lastStart: freeDay.lastStart, now: now, calendar: .current) {
                    Button { freeDay.start() } label: {
                        Text("Try everything free today")
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(SN.leaf)
                } else if let last = freeDay.lastStart {
                    let next = nextFreeDayDate(lastStart: last, calendar: .current)
                    Text("Your next free day is \(next, format: .dateTime.month(.wide).day())")
                        .foregroundStyle(SN.foam.opacity(0.75))
                }
            }
            .font(.subheadline.weight(.semibold))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("premium-free-day")
        }
    }
}
