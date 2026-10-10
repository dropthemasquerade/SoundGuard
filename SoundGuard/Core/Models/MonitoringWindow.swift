import Foundation

/// Clock window for armed listening. Minutes are counted from local midnight.
/// A disabled window, or a window whose start and end match, is always open.
/// When the end is earlier than the start, the window crosses midnight.
struct MonitoringWindow: Equatable, Sendable {
    var enabled: Bool
    var startMinutes: Int
    var endMinutes: Int

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard enabled else { return true }
        let start = Self.clamp(startMinutes)
        let end = Self.clamp(endMinutes)
        if start == end { return true }
        let minute = Self.minuteOfDay(date, calendar: calendar)
        if start < end {
            return minute >= start && minute < end
        }
        return minute >= start || minute < end
    }

    /// Seconds until listening should start or stop. Nil when the window cannot change.
    func secondsUntilBoundary(from date: Date, calendar: Calendar = .current) -> TimeInterval? {
        guard enabled else { return nil }
        let start = Self.clamp(startMinutes)
        let end = Self.clamp(endMinutes)
        guard start != end else { return nil }
        let open = contains(date, calendar: calendar)
        let cursor = calendar.date(bySetting: .second, value: 0, of: date) ?? date
        var next = calendar.date(byAdding: .minute, value: 1, to: cursor) ?? date.addingTimeInterval(60)
        for _ in 0..<(24 * 60 + 2) {
            if contains(next, calendar: calendar) != open {
                return max(1, next.timeIntervalSince(date))
            }
            guard let step = calendar.date(byAdding: .minute, value: 1, to: next) else { return nil }
            next = step
        }
        return nil
    }

    var label: String {
        "\(Self.clock(startMinutes))–\(Self.clock(endMinutes))"
    }

    static func clock(_ minutes: Int) -> String {
        let value = clamp(minutes)
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    static func minuteOfDay(_ date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    static func clamp(_ minutes: Int) -> Int {
        ((minutes % 1440) + 1440) % 1440
    }
}
