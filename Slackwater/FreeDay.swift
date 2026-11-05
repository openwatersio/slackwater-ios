import Foundation

/// One 24-hour stretch of Premium, started by a tap. Widgets, complications and
/// the app all read the same start, so the end holds with the app closed.
struct FreeDay: Codable, Equatable {
    let start: Date
    var end: Date { start + FreeDay.length }

    static var length: TimeInterval {
        #if DEBUG
        // Lets the device check watch a free day end in seconds, not a day.
        if let override = UserDefaults.standard.object(forKey: "freeDayLength") as? Double, override > 0 {
            return override
        }
        #endif
        return 86_400
    }
}

/// Once per calendar month, in the calendar the caller passes, so a free day
/// used late on October 31 locally does not block November 1 just because UTC
/// has already turned over.
func freeDayAvailable(lastStart: Date?, now: Date, calendar: Calendar) -> Bool {
    guard let lastStart else { return true }
    let month: Set<Calendar.Component> = [.year, .month]
    // A clock moved back puts lastStart after now; only the same month blocks.
    return calendar.dateComponents(month, from: lastStart) != calendar.dateComponents(month, from: now)
}

/// The first instant of the month after `lastStart`.
func nextFreeDayDate(lastStart: Date, calendar: Calendar) -> Date {
    let startOfMonth = calendar.dateInterval(of: .month, for: lastStart)?.start ?? lastStart
    return calendar.date(byAdding: .month, value: 1, to: startOfMonth) ?? lastStart
}

/// `start <= date < end`. A start in the future (clock moved back) is not running.
func freeDayRunning(_ day: FreeDay?, at date: Date) -> Bool {
    guard let day else { return false }
    return day.start <= date && date < day.end
}

func premiumActive(purchased: Bool, freeDay: FreeDay?, at date: Date) -> Bool {
    purchased || freeDayRunning(freeDay, at: date)
}
