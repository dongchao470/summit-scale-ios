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

    /// 千卡取整，负号保留。
    static func kcal(_ value: Double) -> String {
        String(format: "%.0f", value)
    }

    static func signedKcal(_ value: Double) -> String {
        String(format: "%+.0f", value)
    }

    static func grams(_ value: Double) -> String {
        String(format: "%.0f", value)
    }

    /// 输入框里的数字解析：容忍中文逗号，非法输入按 0 处理。
    static func number(_ text: String) -> Double {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "，", with: ".")
        return Double(normalized) ?? 0
    }

    static func height(_ value: Double) -> String {
        String(format: "%.0f", value)
    }

    /// 周数取一位小数；超过一年时直接说多少周更直观。
    static func weeks(_ value: Double) -> String {
        if value >= 99 {
            return "99+"
        }
        return String(format: "%.1f", value)
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

    /// 形如"3 天前""今天""昨天"，列表里比时间戳好读。
    static func relativeDay(_ date: Date) -> String {
        let days = calendar.dateComponents([.day], from: startOfDay(date), to: startOfDay(Date())).day ?? 0
        switch days {
        case 0: return "今天"
        case 1: return "昨天"
        case 2...6: return "\(days) 天前"
        default: return day(date)
        }
    }
}
