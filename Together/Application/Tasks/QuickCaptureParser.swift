import Foundation

enum QuickCaptureTimeStatus: Equatable, Sendable {
    case none
    case exact
    case ambiguous
    case unsupported
}

enum QuickCaptureSaveDecision: Equatable, Sendable {
    case autoSave
    case confirmTime
    case saveAsPlainTask
    case suggestPeriodicTask
}

enum QuickCaptureConfirmationKind: Equatable, Sendable {
    case timeOnly
    case dateAndTime
}

struct QuickCaptureParseResult: Equatable, Sendable {
    let rawInput: String
    let normalizedInput: String
    let title: String
    let parsedDate: Date?
    let originalTimePhrase: String?
    let timeStatus: QuickCaptureTimeStatus
    let saveDecision: QuickCaptureSaveDecision
    let confirmationKind: QuickCaptureConfirmationKind
}

protocol QuickCaptureParserProtocol: Sendable {
    func parse(_ input: String, now: Date, calendar: Calendar) -> QuickCaptureParseResult
}

struct RuleBasedQuickCaptureParser: QuickCaptureParserProtocol {
    func parse(_ input: String, now: Date, calendar: Calendar) -> QuickCaptureParseResult {
        let normalizedInput = normalize(input)
        // 每月但未指定具体哪一天 → 建议创建例行事务
        if normalizedInput.contains("每月") && !hasSpecificMonthDay(in: normalizedInput) {
            return QuickCaptureParseResult(
                rawInput: input,
                normalizedInput: normalizedInput,
                title: extractTitle(from: normalizedInput, removing: nil),
                parsedDate: nil,
                originalTimePhrase: nil,
                timeStatus: .unsupported,
                saveDecision: .suggestPeriodicTask,
                confirmationKind: .dateAndTime
            )
        }

        let unsupportedMarkers = ["每周", "每月", "每年", "如果", "下周", "月底", "月末"]
        if unsupportedMarkers.contains(where: { normalizedInput.contains($0) }) {
            return QuickCaptureParseResult(
                rawInput: input,
                normalizedInput: normalizedInput,
                title: extractTitle(from: normalizedInput, removing: nil),
                parsedDate: nil,
                originalTimePhrase: nil,
                timeStatus: .unsupported,
                saveDecision: .saveAsPlainTask,
                confirmationKind: .dateAndTime
            )
        }

        if let relative = parseRelativeOffset(from: normalizedInput, now: now, calendar: calendar) {
            return QuickCaptureParseResult(
                rawInput: input,
                normalizedInput: normalizedInput,
                title: extractTitle(from: normalizedInput, removing: relative.phrase),
                parsedDate: relative.date,
                originalTimePhrase: relative.phrase,
                timeStatus: .exact,
                saveDecision: .autoSave,
                confirmationKind: .timeOnly
            )
        }

        if let absolute = parseAbsoluteDateTime(from: normalizedInput, now: now, calendar: calendar) {
            return QuickCaptureParseResult(
                rawInput: input,
                normalizedInput: normalizedInput,
                title: extractTitle(from: normalizedInput, removing: absolute.phrase),
                parsedDate: absolute.date,
                originalTimePhrase: absolute.phrase,
                timeStatus: .exact,
                saveDecision: .autoSave,
                confirmationKind: .timeOnly
            )
        }

        if let ambiguous = parseAmbiguousDateTime(from: normalizedInput, now: now, calendar: calendar) {
            return QuickCaptureParseResult(
                rawInput: input,
                normalizedInput: normalizedInput,
                title: extractTitle(from: normalizedInput, removing: ambiguous.phrase),
                parsedDate: ambiguous.date,
                originalTimePhrase: ambiguous.phrase,
                timeStatus: .ambiguous,
                saveDecision: .confirmTime,
                confirmationKind: confirmationKind(for: ambiguous.phrase)
            )
        }

        return QuickCaptureParseResult(
            rawInput: input,
            normalizedInput: normalizedInput,
            title: extractTitle(from: normalizedInput, removing: nil),
            parsedDate: nil,
            originalTimePhrase: nil,
            timeStatus: .none,
            saveDecision: .saveAsPlainTask,
            confirmationKind: .timeOnly
        )
    }

    private func confirmationKind(for phrase: String) -> QuickCaptureConfirmationKind {
        if phrase.contains("周末") || phrase.contains("改天") {
            return .dateAndTime
        }
        if phrase.contains("前") && !hasExplicitDateAnchor(in: phrase) {
            return .dateAndTime
        }
        return .timeOnly
    }

    private func normalize(_ input: String) -> String {
        input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "：", with: ":")
            .replacingOccurrences(of: "，", with: " ")
            .replacingOccurrences(of: "。", with: " ")
            .replacingOccurrences(of: "点钟", with: "点")
            .replacingOccurrences(of: "点整", with: "点")
            .replacingOccurrences(of: "  ", with: " ")
    }

    private func parseRelativeOffset(
        from input: String,
        now: Date,
        calendar: Calendar
    ) -> (phrase: String, date: Date)? {
        if let match = firstMatch(
            pattern: #"((?:\d+|[零一二两三四五六七八九十百半]+)\s*(?:分钟|分|小时|个小时))后"#,
            in: input
        ) {
            let phrase = match
            let stripped = phrase.replacingOccurrences(of: "后", with: "")
            if stripped.contains("小时") {
                let hoursPhrase = stripped
                    .replacingOccurrences(of: "个小时", with: "")
                    .replacingOccurrences(of: "小时", with: "")
                    .trimmingCharacters(in: .whitespaces)
                guard let hours = parseChineseOrArabicNumber(hoursPhrase) else { return nil }
                let seconds = Int(hours * 3600)
                guard let date = calendar.date(byAdding: .second, value: seconds, to: now) else { return nil }
                return (phrase, date)
            }

            let minutePhrase = stripped
                .replacingOccurrences(of: "分钟", with: "")
                .replacingOccurrences(of: "分", with: "")
                .trimmingCharacters(in: .whitespaces)
            guard let minutes = parseChineseOrArabicNumber(minutePhrase) else { return nil }
            let seconds = Int(minutes * 60)
            guard let date = calendar.date(byAdding: .second, value: seconds, to: now) else { return nil }
            return (phrase, date)
        }

        return nil
    }

    private func parseAbsoluteDateTime(
        from input: String,
        now: Date,
        calendar: Calendar
    ) -> (phrase: String, date: Date)? {
        let patterns = [
            #"((今天|明天|后天|今早|今晚|明早|明晚|周[一二三四五六日天])\s*(早上|上午|中午|下午|傍晚|晚上)?\s*[零一二两三四五六七八九十\d]{1,3}点(?:半|[零一二两三四五六七八九十\d]{1,2}分?)?)"#,
            #"((今天|明天|后天|今早|今晚|明早|明晚|周[一二三四五六日天])\s*[零一二两三四五六七八九十\d]{1,3}点(?:半|[零一二两三四五六七八九十\d]{1,2}分?)?)"#,
            #"((今天|明天|后天|今早|今晚|明早|明晚|周[一二三四五六日天])\s*(早上|上午|中午|下午|傍晚|晚上)?\s*\d{1,2}:\d{2})"#,
            #"((\d{1,2})月(\d{1,2})日\s*(早上|上午|中午|下午|傍晚|晚上)?\s*[零一二两三四五六七八九十\d]{1,3}点(?:半|[零一二两三四五六七八九十\d]{1,2}分?)?)"#,
            #"((\d{1,2})月(\d{1,2})日\s*(早上|上午|中午|下午|傍晚|晚上)?\s*\d{1,2}:\d{2})"#,
            #"((早上|上午|中午|下午|傍晚|晚上)\s*[零一二两三四五六七八九十\d]{1,3}点(?:半|[零一二两三四五六七八九十\d]{1,2}分?)?)"#,
            #"((早上|上午|中午|下午|傍晚|晚上)\s*\d{1,2}:\d{2})"#
        ]

        for pattern in patterns {
            guard let phrase = firstMatch(pattern: pattern, in: input) else { continue }
            guard let date = resolveDate(from: phrase, now: now, calendar: calendar, ambiguous: false) else { continue }
            return (phrase, date)
        }

        return nil
    }

    private func parseAmbiguousDateTime(
        from input: String,
        now: Date,
        calendar: Calendar
    ) -> (phrase: String, date: Date)? {
        let patterns = [
            #"(明天|后天|今天|今晚|明晚|周末|周[一二三四五六日天])\s*(早上|上午|中午|下午|傍晚|晚上)"#,
            #"(今天|明天|后天)\s*下班前"#,
            #"(晚点|待会|一会儿|下班前)"#,
            #"(周[一二三四五六日天]前|今天前|明天前|后天前)"#,
            #"(周末)"#,
            #"(五一节|劳动节|元旦|国庆节)"#
        ]

        for pattern in patterns {
            guard let phrase = firstMatch(pattern: pattern, in: input) else { continue }
            guard let date = resolveDate(from: phrase, now: now, calendar: calendar, ambiguous: true) else { continue }
            return (phrase, date)
        }

        return nil
    }

    private func resolveDate(
        from phrase: String,
        now: Date,
        calendar: Calendar,
        ambiguous: Bool
    ) -> Date? {
        let baseDate = resolveBaseDate(from: phrase, now: now, calendar: calendar) ?? now
        let explicitTime = extractExplicitTime(from: phrase)
        let mappedTime = explicitTime ?? mapDefaultTime(for: phrase, now: now)

        guard let mappedTime else { return nil }

        var components = calendar.dateComponents([.year, .month, .day], from: baseDate)
        components.hour = mappedTime.hour
        components.minute = mappedTime.minute
        components.second = 0
        guard let date = calendar.date(from: components) else { return nil }

        if ambiguous || date >= now {
            return date
        }

        if !hasExplicitDateAnchor(in: phrase) {
            return calendar.date(byAdding: .day, value: 1, to: date)
        }

        return date
    }

    private func resolveBaseDate(from phrase: String, now: Date, calendar: Calendar) -> Date? {
        if phrase.contains("后天") {
            return calendar.date(byAdding: .day, value: 2, to: now)
        }
        if phrase.contains("明天") || phrase.contains("明早") || phrase.contains("明晚") {
            return calendar.date(byAdding: .day, value: 1, to: now)
        }
        if phrase.contains("今天") || phrase.contains("今早") || phrase.contains("今晚") {
            return now
        }
        if phrase.contains("周末") {
            return nextWeekday(7, from: now, calendar: calendar)
        }
        if let weekday = weekdayNumber(from: phrase) {
            return nextWeekday(weekday, from: now, calendar: calendar)
        }
        if let monthDay = extractMonthDay(from: phrase, calendar: calendar, referenceDate: now) {
            return monthDay
        }
        if let holidayDate = extractHolidayDate(from: phrase, calendar: calendar, referenceDate: now) {
            return holidayDate
        }
        return now
    }

    private func extractExplicitTime(from phrase: String) -> (hour: Int, minute: Int)? {
        if let clockGroups = regexGroups(pattern: #"(\d{1,2}):(\d{2})"#, in: phrase),
           let rawHour = clockGroups[safe: 1],
           let rawMinute = clockGroups[safe: 2],
           let hour = Int(rawHour),
           let minute = Int(rawMinute) {
            let adjustedHour = adjustedHourForPeriod(hour: hour, phrase: phrase)
            return (adjustedHour, minute)
        }

        guard let match = regexGroups(
            pattern: #"([零一二两三四五六七八九十\d]{1,3})点(?:([零一二两三四五六七八九十\d]{1,2})分?|半)?"#,
            in: phrase
        ) else {
            return nil
        }

        guard let rawHour = match[safe: 1], let hour = parseChineseInt(rawHour) else { return nil }
        let minute: Int
        if phrase.contains("半") {
            minute = 30
        } else if let rawMinute = match[safe: 2], let parsedMinute = parseChineseInt(rawMinute) {
            minute = parsedMinute
        } else {
            minute = 0
        }

        let adjustedHour = adjustedHourForPeriod(hour: hour, phrase: phrase)
        return (adjustedHour, minute)
    }

    private func mapDefaultTime(for phrase: String, now: Date) -> (hour: Int, minute: Int)? {
        if phrase.contains("待会") || phrase.contains("一会儿") {
            let target = now.addingTimeInterval(30 * 60)
            let components = Calendar.current.dateComponents([.hour, .minute], from: target)
            return (components.hour ?? 0, components.minute ?? 0)
        }
        if phrase.contains("晚点") {
            let target = now.addingTimeInterval(60 * 60)
            let components = Calendar.current.dateComponents([.hour, .minute], from: target)
            return (components.hour ?? 0, components.minute ?? 0)
        }
        if phrase.contains("下班前") {
            return (18, 0)
        }
        if phrase.contains("早上") || phrase.contains("今早") || phrase.contains("明早") {
            return (9, 0)
        }
        if phrase.contains("上午") {
            return (10, 0)
        }
        if phrase.contains("中午") {
            return (12, 30)
        }
        if phrase.contains("下午") {
            return (15, 0)
        }
        if phrase.contains("傍晚") {
            return (18, 0)
        }
        if phrase.contains("晚上") || phrase.contains("今晚") || phrase.contains("明晚") {
            return (20, 0)
        }
        if phrase.contains("周末") {
            return (10, 0)
        }
        if isKnownHoliday(phrase) {
            return (10, 0)
        }
        if phrase.contains("前") {
            return (18, 0)
        }
        return nil
    }

    private func adjustedHourForPeriod(hour: Int, phrase: String) -> Int {
        if phrase.contains("下午") || phrase.contains("晚上") || phrase.contains("傍晚") || phrase.contains("今晚") || phrase.contains("明晚") {
            if hour < 12 { return hour + 12 }
        }
        if phrase.contains("中午"), hour < 11 {
            return hour + 12
        }
        return hour
    }

    private func extractMonthDay(from phrase: String, calendar: Calendar, referenceDate: Date) -> Date? {
        guard let groups = regexGroups(pattern: #"(\d{1,2})月(\d{1,2})日"#, in: phrase),
              let monthText = groups[safe: 1],
              let dayText = groups[safe: 2],
              let month = Int(monthText),
              let day = Int(dayText) else {
            return nil
        }

        var components = calendar.dateComponents([.year], from: referenceDate)
        components.month = month
        components.day = day
        return calendar.date(from: components)
    }

    private func extractTitle(from input: String, removing timePhrase: String?) -> String {
        var value = input
        if let timePhrase, !timePhrase.isEmpty {
            value = value.replacingOccurrences(of: timePhrase, with: " ")
        }

        value = value
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))

        let leadingMarkers = ["提醒我", "提醒", "记得", "帮我", "请我", "请", "待会", "一会儿", "晚点"]
        var removedLeadingMarker = true
        while removedLeadingMarker {
            removedLeadingMarker = false
            for marker in leadingMarkers where value.hasPrefix(marker) {
                value = String(value.dropFirst(marker.count))
                    .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
                removedLeadingMarker = true
            }
        }

        value = value
            .replacingOccurrences(of: "提醒我", with: " ")
            .replacingOccurrences(of: "提醒", with: " ")
            .replacingOccurrences(of: "记得", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))

        if value.isEmpty {
            return input.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return value
    }

    private func nextWeekday(_ weekday: Int, from now: Date, calendar: Calendar) -> Date? {
        let currentWeekday = calendar.component(.weekday, from: now)
        let delta = (weekday - currentWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: delta == 0 ? 7 : delta, to: now)
    }

    private func weekdayNumber(from phrase: String) -> Int? {
        let mapping: [String: Int] = [
            "周日": 1, "周天": 1, "周一": 2, "周二": 3, "周三": 4,
            "周四": 5, "周五": 6, "周六": 7
        ]
        return mapping.first(where: { phrase.contains($0.key) })?.value
    }

    private func hasExplicitDateAnchor(in phrase: String) -> Bool {
        if phrase.contains("今天") || phrase.contains("明天") || phrase.contains("后天") ||
            phrase.contains("今早") || phrase.contains("今晚") || phrase.contains("明早") || phrase.contains("明晚") {
            return true
        }
        if weekdayNumber(from: phrase) != nil {
            return true
        }
        if phrase.contains("周末") {
            return false
        }
        if extractMonthDay(from: phrase, calendar: .current, referenceDate: Date()) != nil {
            return true
        }
        return isKnownHoliday(phrase)
    }

    private func isKnownHoliday(_ phrase: String) -> Bool {
        ["五一节", "劳动节", "元旦", "国庆节"].contains(where: { phrase.contains($0) })
    }

    // 判断输入是否指定了每月具体哪一天（如"每月15号"、"每月第3天"）
    private func hasSpecificMonthDay(in input: String) -> Bool {
        let pattern = #"每月\s*(?:\d+|[一二三四五六七八九十百]+)\s*[号日]|每月第\s*(?:\d+|[一二三四五六七八九十]+)\s*[天日周]"#
        return firstMatch(pattern: pattern, in: input) != nil
    }

    private func extractHolidayDate(from phrase: String, calendar: Calendar, referenceDate: Date) -> Date? {
        let monthDay: (Int, Int)?
        switch true {
        case phrase.contains("五一节"), phrase.contains("劳动节"):
            monthDay = (5, 1)
        case phrase.contains("元旦"):
            monthDay = (1, 1)
        case phrase.contains("国庆节"):
            monthDay = (10, 1)
        default:
            monthDay = nil
        }

        guard let monthDay else { return nil }
        var components = calendar.dateComponents([.year], from: referenceDate)
        components.month = monthDay.0
        components.day = monthDay.1
        guard let date = calendar.date(from: components) else { return nil }
        if date >= referenceDate {
            return date
        }
        components.year = (components.year ?? calendar.component(.year, from: referenceDate)) + 1
        return calendar.date(from: components)
    }

    private func firstMatch(pattern: String, in input: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        guard let match = regex.firstMatch(in: input, range: range),
              let matchRange = Range(match.range(at: 0), in: input) else {
            return nil
        }
        return String(input[matchRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func regexGroups(pattern: String, in input: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        guard let match = regex.firstMatch(in: input, range: range) else { return nil }
        return (0..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: input) else { return nil }
            return String(input[range])
        }
    }

    private func parseChineseOrArabicNumber(_ input: String) -> Double? {
        if input == "半" { return 0.5 }
        if let value = Double(input) { return value }
        if let value = parseChineseInt(input) { return Double(value) }
        return nil
    }

    private func parseChineseInt(_ input: String) -> Int? {
        if let value = Int(input) { return value }

        let digits: [Character: Int] = [
            "零": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4,
            "五": 5, "六": 6, "七": 7, "八": 8, "九": 9
        ]

        if input == "十" { return 10 }
        if input.hasPrefix("十"), let last = input.last, let digit = digits[last] {
            return 10 + digit
        }
        if input.hasSuffix("十"), let first = input.first, let digit = digits[first] {
            return digit * 10
        }
        if input.count == 2 {
            let chars = Array(input)
            if chars[1] == "十", let digit = digits[chars[0]] {
                return digit * 10
            }
            if chars[0] == "十", let digit = digits[chars[1]] {
                return 10 + digit
            }
        }
        if input.count == 3 {
            let chars = Array(input)
            if chars[1] == "十", let tens = digits[chars[0]], let ones = digits[chars[2]] {
                return tens * 10 + ones
            }
        }

        if input.count == 1, let char = input.first, let digit = digits[char] {
            return digit
        }
        return nil
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
