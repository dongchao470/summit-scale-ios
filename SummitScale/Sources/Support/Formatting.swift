import Foundation

enum Fmt {
    static let calendar = Calendar.current

    private static let shortDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter
    }()

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.setLocalizedDateFormatFromTemplate("MMMd HH:mm")
        return formatter
    }()

    static func day(_ date: Date) -> String {
        shortDay.string(from: date)
    }

    static func stamp(_ date: Date) -> String {
        stampFormatter.string(from: date)
    }

    static func kg(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    static func signedKg(_ value: Double) -> String {
        String(format: "%+.1f", value)
    }

    static func km(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    static func meters(_ value: Double) -> String {
        String(format: "%.0f", value)
    }

    static func minutes(_ value: Double) -> String {
        let total = Int(value.rounded())
        if total >= 60 {
            return "\(total / 60)h" + String(format: "%02d", total % 60) + "m"
        }
        return "\(total)m"
    }

    static func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    static func startOfWeek(_ date: Date) -> Date {
        var weekCalendar = calendar
        weekCalendar.firstWeekday = 2
        let components = weekCalendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return weekCalendar.date(from: components) ?? weekCalendar.startOfDay(for: date)
    }

    static func daysAgo(_ days: Int) -> Date {
        calendar.date(byAdding: .day, value: -days, to: Date()) ?? Date()
    }
}
