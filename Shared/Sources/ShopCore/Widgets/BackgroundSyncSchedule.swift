import Foundation

public enum BackgroundSyncSchedule {
    /// Daytime (07:00–22:00 local): +1 hour. Night: +3 hours.
    /// `earliestBeginDate` only — system may delay further.
    public static func nextEarliestBeginDate(
        after date: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        let hour = calendar.component(.hour, from: date)
        let interval: TimeInterval = (hour >= 7 && hour < 22) ? 3600 : 3 * 3600
        return date.addingTimeInterval(interval)
    }
}
