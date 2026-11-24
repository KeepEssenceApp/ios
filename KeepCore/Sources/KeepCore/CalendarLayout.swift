import Foundation

/// How one day of the calendar is drawn. Five marks, as in the product definition:
/// nothing saved, saved without a digest yet, a digest not read, a digest read, a note kept.
public enum DayDot: String, Equatable, Sendable {
    /// A very small grey dot.
    case empty
    /// A grey ring.
    case saved
    /// A ring in the text colour.
    case digestUnread
    /// A solid dot in the text colour.
    case digestRead
    /// A solid gold dot.
    case note
}

public struct CalendarCell: Equatable, Identifiable, Sendable {
    public let day: String
    /// Day of the month, 1...31.
    public let number: Int
    public let dot: DayDot
    public let isToday: Bool
    /// A day opens its daily digest; without one it cannot be pressed.
    public let opensDigest: Bool
    public var id: String { day }
}

public enum CalendarLayout {
    public static func dot(forMark mark: String) -> DayDot? {
        switch mark {
        case "empty": return .empty
        case "saved": return .saved
        case "digest_unread": return .digestUnread
        case "digest_read": return .digestRead
        case "note": return .note
        default: return nil     // `future`, and anything this version does not know: not drawn
        }
    }

    /// The days to draw, in date order. Days in the future are left out.
    public static func cells(_ month: CalendarMonth) -> [CalendarCell] {
        month.days.sorted { $0.day < $1.day }.compactMap { d in
            guard let dot = dot(forMark: d.mark), let number = Int(d.day.suffix(2)) else { return nil }
            return CalendarCell(day: d.day, number: number, dot: dot, isToday: d.day == month.today,
                                opensDigest: d.hasDigest ?? (dot == .digestUnread || dot == .digestRead))
        }
    }

    /// Seven to a row, by date, not by weekday.
    public static func rows(_ month: CalendarMonth, perRow: Int = 7) -> [[CalendarCell]] {
        let all = cells(month)
        return stride(from: 0, to: all.count, by: perRow).map { Array(all[$0..<min($0 + perRow, all.count)]) }
    }
}

public enum KeepDates {
    /// `2026-11-24` to a date at noon in the current calendar, for display only.
    public static func date(fromDay day: String) -> Date? {
        let p = day.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))
    }

    public static func dayTitle(_ day: String, locale: Locale = .current) -> String {
        guard let d = date(fromDay: day) else { return day }
        let f = DateFormatter()
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("MMMd")
        return f.string(from: d)
    }

    public static func monthTitle(_ month: String, locale: Locale = .current) -> String {
        guard let d = date(fromDay: month + "-01") else { return month }
        let f = DateFormatter()
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("yMMMM")
        return f.string(from: d)
    }

    public static func time(_ date: Date, locale: Locale = .current) -> String {
        let f = DateFormatter()
        f.locale = locale
        if Calendar.current.isDateInToday(date) {
            f.setLocalizedDateFormatFromTemplate("Hm")
        } else {
            f.setLocalizedDateFormatFromTemplate("MMMdHm")
        }
        return f.string(from: date)
    }

    public static func ago(_ date: Date, now: Date = Date(), locale: Locale = .current) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = locale
        f.unitsStyle = .full
        return f.localizedString(for: min(date, now), relativeTo: now)
    }
}
