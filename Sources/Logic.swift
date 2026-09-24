import Foundation

enum Logic {
    static let appName = "日程台"
    static let schemaVersion = 1

    static var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.firstWeekday = 1
        return calendar
    }()

    static let weekdayLong = ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"]
    static let weekdayShort = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
    static let units = ["day", "week", "month", "year"]
    static let unitLabels = ["日", "周", "月", "年"]

    static func nowStamp(_ date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    static func parse(_ string: String) -> Date? {
        let parts = string.split(separator: "T", omittingEmptySubsequences: false)
        let dateBits = parts[0].split(separator: "-")
        guard dateBits.count == 3, let year = Int(dateBits[0]), let month = Int(dateBits[1]), let day = Int(dateBits[2]) else {
            return nil
        }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        if parts.count > 1 {
            let timeBits = parts[1].split(separator: ":")
            components.hour = Int(timeBits.first ?? "0") ?? 0
            components.minute = timeBits.count > 1 ? Int(timeBits[1]) ?? 0 : 0
        }
        return calendar.date(from: components)
    }

    static func format(_ date: Date, time: Bool) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        guard time else { return day }
        return String(format: "%@T%02d:%02d", day, parts.hour ?? 0, parts.minute ?? 0)
    }

    static func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    static func addDays(_ date: Date, _ days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    static func daysBetween(_ start: Date, _ end: Date) -> Int {
        calendar.dateComponents([.day], from: startOfDay(start), to: startOfDay(end)).day ?? 0
    }

    static func daysInMonth(year: Int, month: Int) -> Int {
        let components = DateComponents(year: year, month: month, day: 1)
        guard let date = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: date) else { return 30 }
        return range.count
    }

    static func addMonths(_ date: Date, _ months: Int) -> Date {
        let original = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        var first = DateComponents()
        first.year = original.year
        first.month = (original.month ?? 1) + months
        first.day = 1
        first.hour = original.hour
        first.minute = original.minute
        guard let anchor = calendar.date(from: first) else { return date }
        let lastDay = calendar.range(of: .day, in: .month, for: anchor)?.count ?? 28
        var clamped = calendar.dateComponents([.year, .month, .hour, .minute], from: anchor)
        clamped.day = min(original.day ?? 1, lastDay)
        return calendar.date(from: clamped) ?? date
    }

    static func nextHour(_ date: Date = Date()) -> Date {
        let parts = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        return calendar.date(from: parts).flatMap { calendar.date(byAdding: .hour, value: 1, to: $0) } ?? date
    }

    static func defaultEnd(start: Date, allDay: Bool) -> Date {
        if allDay { return startOfDay(start) }
        return calendar.date(byAdding: .hour, value: 1, to: start) ?? start.addingTimeInterval(3600)
    }

    static func component(_ date: Date, _ unit: Calendar.Component) -> Int {
        calendar.component(unit, from: date)
    }

    static func compose(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        let clampedDay = min(max(day, 1), daysInMonth(year: year, month: month))
        return calendar.date(from: DateComponents(year: year, month: month, day: clampedDay, hour: hour, minute: minute)) ?? Date()
    }

    static func weekdayIndex(_ date: Date) -> Int {
        calendar.component(.weekday, from: date) - 1
    }

    static func dayHeading(_ date: Date, today: Date) -> String {
        "\(component(date, .month))月\(component(date, .day))日 \(weekdayShort[weekdayIndex(date)])"
    }

    static func clock(_ date: Date) -> String {
        String(format: "%02d:%02d", component(date, .hour), component(date, .minute))
    }

    static func hexColor(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let body = text.hasPrefix("#") ? String(text.dropFirst()) : text
        guard body.count == 6, body.allSatisfy({ $0.isHexDigit }) else { return nil }
        return "#\(body)"
    }

    static func monthDay(_ date: Date) -> String {
        "\(component(date, .month))月\(component(date, .day))日"
    }

    static func repeatSummary(_ rule: RepeatRule, start: Date) -> String {
        switch rule.type {
        case "daily":
            return "每天"
        case "weekly":
            return "每周 · \(weekdayShort[weekdayIndex(start)])"
        case "monthly":
            return "每月 · \(component(start, .day))日"
        case "yearly":
            return "每年 · \(monthDay(start))"
        case "custom":
            return customSummary(rule)
        default:
            return "不重复"
        }
    }

    static func customSummary(_ rule: RepeatRule) -> String {
        let unit = unitLabels[units.firstIndex(of: rule.unit) ?? 1]
        var text = "每\(max(rule.interval, 1))\(unit)"
        if rule.unit == "week" {
            let days = (rule.weekdays.isEmpty ? [weekdayIndex(Date())] : rule.weekdays).sorted()
            text += " · " + days.map { weekdayShort[$0] }.joined(separator: "、")
        }
        if rule.endMode == "until", let until = rule.until, let date = parse(until) {
            text += " · 至\(component(date, .year))年\(monthDay(date))"
        }
        return text
    }

    static func everyLabel(interval: Int, unitIndex: Int) -> String {
        "每\(interval)\(unitLabels[min(max(unitIndex, 0), 3)])"
    }

    static func normalizedRule(_ rule: RepeatRule, start: Date) -> RepeatRule? {
        switch rule.type {
        case "none":
            return nil
        case "daily":
            return RepeatRule(type: "custom", interval: 1, unit: "day", weekdays: [], endMode: "forever", until: nil)
        case "weekly":
            return RepeatRule(type: "custom", interval: 1, unit: "week", weekdays: [weekdayIndex(start)], endMode: "forever", until: nil)
        case "monthly":
            return RepeatRule(type: "custom", interval: 1, unit: "month", weekdays: [], endMode: "forever", until: nil)
        case "yearly":
            return RepeatRule(type: "custom", interval: 1, unit: "year", weekdays: [], endMode: "forever", until: nil)
        case "custom":
            var copy = rule
            copy.interval = min(99, max(1, copy.interval))
            if !units.contains(copy.unit) { copy.unit = "week" }
            copy.weekdays = Array(Set(copy.weekdays.filter { (0...6).contains($0) })).sorted()
            if copy.unit == "week" && copy.weekdays.isEmpty {
                copy.weekdays = [weekdayIndex(start)]
            }
            if copy.endMode != "until" { copy.endMode = "forever" }
            return copy
        default:
            return nil
        }
    }

    static func customDraft(from rule: RepeatRule, start: Date) -> RepeatRule {
        if rule.type == "custom" {
            return normalizedRule(rule, start: start) ?? rule
        }
        let mapped = normalizedRule(rule.type == "none" ? RepeatRule(type: "weekly", interval: 1, unit: "week", weekdays: [], endMode: "forever", until: nil) : rule, start: start)
        var draft = mapped ?? RepeatRule(type: "custom", interval: 1, unit: "week", weekdays: [weekdayIndex(start)], endMode: "forever", until: nil)
        draft.type = "custom"
        draft.endMode = "forever"
        draft.until = nil
        return draft
    }

    static func eventSpan(_ event: ScheduleEvent) -> (start: Date, end: Date)? {
        guard let start = parse(event.start) else { return nil }
        if event.allDay {
            let startDay = startOfDay(start)
            let endDay = startOfDay(parse(event.end) ?? start)
            let days = max(1, daysBetween(startDay, endDay) + 1)
            let end = addDays(startDay, days)
            return (startDay, end)
        }
        let end = parse(event.end) ?? defaultEnd(start: start, allDay: false)
        guard end > start else { return nil }
        return (start, end)
    }

    static func expand(_ event: ScheduleEvent, from rangeStart: Date, to rangeEnd: Date) -> [Occurrence] {
        guard let span = eventSpan(event), rangeEnd > rangeStart else { return [] }
        let duration = span.end.timeIntervalSince(span.start)
        guard let rule = normalizedRule(event.repeatRule, start: span.start) else {
            if span.end > rangeStart && span.start < rangeEnd {
                return [Occurrence(event: event, start: span.start, end: span.end, conflict: false)]
            }
            return []
        }
        let until: Date? = {
            guard rule.endMode == "until", let raw = rule.until, let date = parse(raw) else { return nil }
            return startOfDay(date)
        }()
        var results: [Occurrence] = []
        func emit(_ start: Date) {
            if event.excludedDates.contains(format(startOfDay(start), time: false)) { return }
            let end = event.allDay ? addDays(startOfDay(start), max(1, daysBetween(span.start, span.end))) : start.addingTimeInterval(duration)
            guard end > rangeStart, start < rangeEnd else { return }
            if let until, startOfDay(start) > until { return }
            if startOfDay(start) < startOfDay(span.start) { return }
            if !event.allDay && start + 1 < span.start { return }
            results.append(Occurrence(event: event, start: start, end: end, conflict: false))
        }

        switch rule.unit {
        case "day":
            let origin = startOfDay(span.start)
            var index = 0
            if rangeStart > span.start {
                let lead = rangeStart.addingTimeInterval(-duration - 86_400)
                index = max(0, daysBetween(origin, lead) / rule.interval)
            }
            for step in 0..<500 {
                let day = addDays(origin, (index + step) * rule.interval)
                let start = event.allDay ? day : matchingTime(day, span.start)
                if let until, startOfDay(start) > until { break }
                if start >= rangeEnd && day > rangeEnd { break }
                if start > rangeEnd.addingTimeInterval(duration) { break }
                emit(start)
                if day > rangeEnd { break }
            }
        case "week":
            let origin = startOfDay(span.start)
            let begin = startOfDay(rangeStart.addingTimeInterval(-duration - 86_400))
            let lower = max(origin, addDays(begin, -7))
            var day = lower
            var guardCount = 0
            while day < rangeEnd && guardCount < 800 {
                let weeks = weeksBetween(origin, day)
                if weeks >= 0, weeks % rule.interval == 0, rule.weekdays.contains(weekdayIndex(day)) {
                    emit(event.allDay ? startOfDay(day) : matchingTime(day, span.start))
                }
                day = addDays(day, 1)
                guardCount += 1
            }
        default:
            let months = rule.unit == "year" ? 12 * rule.interval : rule.interval
            for step in 0..<240 {
                let shifted = addMonths(span.start, step * months)
                if let until, startOfDay(shifted) > until { break }
                if shifted > rangeEnd.addingTimeInterval(duration) { break }
                emit(event.allDay ? startOfDay(shifted) : shifted)
                if shifted > rangeEnd { break }
            }
        }
        return results
    }

    static func matchingTime(_ day: Date, _ time: Date) -> Date {
        let dayParts = calendar.dateComponents([.year, .month, .day], from: day)
        let timeParts = calendar.dateComponents([.hour, .minute], from: time)
        var components = DateComponents()
        components.year = dayParts.year
        components.month = dayParts.month
        components.day = dayParts.day
        components.hour = timeParts.hour
        components.minute = timeParts.minute
        return calendar.date(from: components) ?? day
    }

    static func weeksBetween(_ start: Date, _ end: Date) -> Int {
        let origin = startOfWeek(start)
        let other = startOfWeek(end)
        return daysBetween(origin, other) / 7
    }

    static func startOfWeek(_ date: Date) -> Date {
        let weekday = calendar.component(.weekday, from: date)
        return addDays(startOfDay(date), -(weekday - 1))
    }

    static func markConflicts(_ items: [Occurrence]) -> [Occurrence] {
        var copy = items.sorted { $0.start < $1.start }
        for index in copy.indices {
            var next = index + 1
            while next < copy.count, copy[next].start < copy[index].end {
                if copy[index].event.id != copy[next].event.id {
                    copy[index].conflict = true
                    copy[next].conflict = true
                }
                next += 1
            }
        }
        return copy
    }

    static func agenda(events: [ScheduleEvent], now: Date, days: Int = 90, pastDays: Int = 0) -> [DayGroup] {
        let today = startOfDay(now)
        let end = addDays(today, days)
        let pastStart = addDays(today, -pastDays)
        let marked = markConflicts(events.flatMap { expand($0, from: pastStart, to: end) })
        var buckets: [String: [Occurrence]] = [:]
        for item in marked {
            let day = displayDay(item, today: today)
            guard day >= pastStart, day < end else { continue }
            buckets[format(day, time: false), default: []].append(item)
        }
        var groups: [DayGroup] = []
        if pastDays > 0 {
            for offset in stride(from: pastDays, through: 1, by: -1) {
                let day = addDays(today, -offset)
                let key = format(day, time: false)
                let items = (buckets[key] ?? []).sorted { $0.start < $1.start }
                if !items.isEmpty { groups.append(DayGroup(date: day, items: items)) }
            }
        }
        for offset in 0..<days {
            let day = addDays(today, offset)
            let key = format(day, time: false)
            let items = (buckets[key] ?? []).sorted { $0.start < $1.start }
            if offset < 3 || !items.isEmpty {
                groups.append(DayGroup(date: day, items: items))
            }
        }
        return groups
    }

    static func displayDay(_ item: Occurrence, today: Date) -> Date {
        let start = startOfDay(item.start)
        if start < today && item.end > today { return today }
        return start
    }

    static func conflicts(for draft: ScheduleEvent, among events: [ScheduleEvent]) -> [String] {
        let start = parse(draft.start) ?? Date()
        let from = addDays(startOfDay(min(start, Date())), -1)
        let to = addDays(from, 366)
        let mine = expand(draft, from: from, to: to)
        let others = events.filter { $0.id != draft.id }.flatMap { expand($0, from: from, to: to) }
        var titles: [String] = []
        for item in mine {
            for other in others where other.event.id != item.event.id && item.start < other.end && other.start < item.end {
                if !titles.contains(other.event.title) { titles.append(other.event.title) }
                if titles.count == 3 { return titles }
            }
        }
        return titles
    }

    static func timeLabel(_ item: Occurrence) -> (start: String, end: String) {
        if item.event.allDay {
            let days = max(1, daysBetween(item.start, item.end))
            if days <= 1 { return ("全天", "") }
            let last = addDays(item.end, -1)
            return ("全天", "至\(monthDay(last))")
        }
        let endText = startOfDay(item.end) > startOfDay(item.start) ? "次日\(clock(item.end))" : clock(item.end)
        return (clock(item.start), endText)
    }

    static func dueLabel(_ date: Date, now: Date) -> String {
        let diff = daysBetween(now, date)
        if diff == 0 { return "今天 \(clock(date))" }
        if diff == 1 { return "明天 \(clock(date))" }
        if diff == -1 { return "昨天 \(clock(date))" }
        return "\(monthDay(date)) \(clock(date))"
    }

    static func notifyMoment(_ item: Occurrence) -> Date {
        guard item.event.allDay else { return item.start }
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: item.start) ?? item.start
    }

    static func occurrenceKey(kind: String, id: UUID, start: Date, allDay: Bool) -> String {
        "\(kind):\(id.uuidString)@\(format(start, time: !allDay))"
    }

    static func splitReminders(_ items: [ReminderItem], now: Date) -> (open: [ReminderItem], done: [ReminderItem]) {
        let open = items.filter { !$0.completed }.sorted { lhs, rhs in
            switch (lhs.due.flatMap(parse), rhs.due.flatMap(parse)) {
            case let (left?, right?):
                return left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.createdAt < rhs.createdAt
            }
        }
        let done = items.filter(\.completed).sorted { ($0.completedAt ?? "") > ($1.completedAt ?? "") }
        return (open, done)
    }

    static func dueItems(_ database: Database, now: Date, grace: TimeInterval = 15 * 60) -> [Notice] {
        var notices: [Notice] = []
        let horizon = addDays(now, 2)
        for event in database.events {
            for item in expand(event, from: addDays(now, -1), to: horizon) {
                let when = notifyMoment(item)
                if database.preferences.earlyReminder && !event.allDay {
                    let early = when.addingTimeInterval(-5 * 60)
                    if early <= now, now.timeIntervalSince(early) <= grace {
                        let earlyKey = occurrenceKey(kind: "event", id: event.id, start: item.start, allDay: false) + "#early"
                        if !shouldSkip(earlyKey, state: database.notificationState, now: now) {
                            notices.append(Notice(key: earlyKey, kind: "event", title: "日程\(event.title)马上就要开始了", notes: event.notes, when: "\(clock(item.start)) – \(clock(item.end))", conflict: false, refID: event.id))
                        }
                    }
                }
                guard when <= now, now.timeIntervalSince(when) <= grace else { continue }
                let key = occurrenceKey(kind: "event", id: event.id, start: item.start, allDay: event.allDay)
                if shouldSkip(key, state: database.notificationState, now: now) { continue }
                let label = event.allDay ? "全天" : "\(clock(item.start)) – \(clock(item.end))"
                notices.append(Notice(key: key, kind: "event", title: event.title, notes: event.notes, when: label, conflict: false, refID: event.id))
            }
        }
        let marked = markConflicts(database.events.flatMap { expand($0, from: addDays(now, -1), to: horizon) })
        for index in notices.indices where notices[index].kind == "event" {
            notices[index].conflict = marked.contains { occurrenceKey(kind: "event", id: $0.event.id, start: $0.start, allDay: $0.event.allDay) == notices[index].key && $0.conflict }
        }
        for reminder in database.reminders where !reminder.completed {
            guard let dueRaw = reminder.due, let due = parse(dueRaw) else { continue }
            guard due <= now, now.timeIntervalSince(due) <= grace else { continue }
            let key = occurrenceKey(kind: "reminder", id: reminder.id, start: due, allDay: false)
            if shouldSkip(key, state: database.notificationState, now: now) { continue }
            notices.append(Notice(key: key, kind: "reminder", title: reminder.title, notes: reminder.notes, when: dueLabel(due, now: now), conflict: false, refID: reminder.id))
        }
        return notices
    }

    static func shouldSkip(_ key: String, state: NotificationState, now: Date) -> Bool {
        if state.fired[key] != nil { return true }
        if let raw = state.snoozed[key], let until = ISO8601DateFormatter().date(from: raw), until > now { return true }
        return false
    }

    static func nextWake(_ database: Database, now: Date) -> Date? {
        var candidate: Date?
        func consider(_ date: Date) {
            guard date > now else { return }
            if candidate == nil || date < candidate! { candidate = date }
        }
        for event in database.events {
            for item in expand(event, from: addDays(now, -1), to: addDays(now, 3)) {
                let when = notifyMoment(item)
                let key = occurrenceKey(kind: "event", id: event.id, start: item.start, allDay: event.allDay)
                if database.preferences.earlyReminder && !event.allDay {
                    let earlyKey = key + "#early"
                    let early = when.addingTimeInterval(-5 * 60)
                    if database.notificationState.fired[earlyKey] == nil { consider(early) }
                }
                if let raw = database.notificationState.snoozed[key], let until = ISO8601DateFormatter().date(from: raw), until > now {
                    consider(until)
                } else if database.notificationState.fired[key] == nil {
                    consider(when)
                }
            }
        }
        for reminder in database.reminders where !reminder.completed {
            guard let dueRaw = reminder.due, let due = parse(dueRaw) else { continue }
            let key = occurrenceKey(kind: "reminder", id: reminder.id, start: due, allDay: false)
            if let raw = database.notificationState.snoozed[key], let until = ISO8601DateFormatter().date(from: raw), until > now {
                consider(until)
            } else if database.notificationState.fired[key] == nil {
                consider(due)
            }
        }
        return candidate
    }

    static func runSelfTest() {
        var failed = 0
        func check(_ condition: Bool, _ message: String) {
            if condition {
                print("ok \(message)")
            } else {
                fputs("FAIL \(message)\n", stderr)
                failed += 1
            }
        }

        let start = compose(year: 2026, month: 9, day: 24, hour: 10, minute: 0)
        check(weekdayIndex(start) == 4, "2026-09-24 is Thursday")
        let end = defaultEnd(start: start, allDay: false)
        check(format(end, time: true) == "2026-09-24T11:00", "default end is one hour later")
        check(daysInMonth(year: 2026, month: 2) == 28, "2026 February has 28 days")
        check(component(addMonths(compose(year: 2026, month: 1, day: 31, hour: 9, minute: 0), 1), .day) == 28, "Jan 31 rolls to Feb 28")
        check(component(addMonths(compose(year: 2024, month: 1, day: 31, hour: 9, minute: 0), 1), .day) == 29, "leap day clamp")

        let morning = ScheduleEvent.make(title: "评审", start: "2026-09-24T10:00", end: "2026-09-24T11:00")
        let overlap = ScheduleEvent.make(title: "同步", start: "2026-09-24T10:30", end: "2026-09-24T12:00")
        let touch = ScheduleEvent.make(title: "下一场", start: "2026-09-24T12:00", end: "2026-09-24T13:00")
        let marked = markConflicts(( [morning, overlap, touch]).flatMap { expand($0, from: compose(year: 2026, month: 9, day: 24), to: compose(year: 2026, month: 9, day: 25)) })
        check(marked.first { $0.event.title == "评审" }?.conflict == true, "overlap conflicts")
        check(marked.first { $0.event.title == "同步" }?.conflict == true, "other side conflicts")
        check(marked.first { $0.event.title == "下一场" }?.conflict == false, "touching boundary is not a conflict")

        let allA = ScheduleEvent.make(title: "出差", start: "2026-09-24", end: "2026-09-24", allDay: true)
        let allB = ScheduleEvent.make(title: "假日", start: "2026-09-24", end: "2026-09-24", allDay: true)
        let allC = ScheduleEvent.make(title: "次日", start: "2026-09-25", end: "2026-09-25", allDay: true)
        let allMarked = markConflicts(([allA, allB, allC]).flatMap { expand($0, from: compose(year: 2026, month: 9, day: 24), to: compose(year: 2026, month: 9, day: 26)) })
        check(allMarked.first { $0.event.title == "出差" }?.conflict == true, "same-day all-day conflicts")
        check(allMarked.first { $0.event.title == "次日" }?.conflict == false, "next-day all-day does not conflict")

        var weekly = ScheduleEvent.make(title: "例会", start: "2026-09-24T10:00", end: "2026-09-24T11:00")
        weekly.repeatRule = RepeatRule(type: "custom", interval: 1, unit: "week", weekdays: [4], endMode: "forever", until: nil)
        let weeklyHits = expand(weekly, from: compose(year: 2026, month: 9, day: 24), to: compose(year: 2026, month: 10, day: 16)).map { format($0.start, time: false) }
        check(weeklyHits == ["2026-09-24", "2026-10-01", "2026-10-08", "2026-10-15"], "every Thursday")
        weekly.excludedDates = ["2026-10-01"]
        let skipped = expand(weekly, from: compose(year: 2026, month: 9, day: 24), to: compose(year: 2026, month: 10, day: 16)).map { format($0.start, time: false) }
        check(skipped == ["2026-09-24", "2026-10-08", "2026-10-15"], "excluded day is removed")
        weekly.excludedDates = []

        weekly.repeatRule.interval = 2
        let biweekly = expand(weekly, from: compose(year: 2026, month: 9, day: 24), to: compose(year: 2026, month: 10, day: 16)).map { format($0.start, time: false) }
        check(biweekly == ["2026-09-24", "2026-10-08"], "every two weeks")

        var daily = ScheduleEvent.make(title: "服药", start: "2026-09-24T08:00", end: "2026-09-24T08:05")
        daily.repeatRule = RepeatRule(type: "daily", interval: 1, unit: "day", weekdays: [], endMode: "forever", until: nil)
        daily.repeatRule = RepeatRule(type: "custom", interval: 2, unit: "day", weekdays: [], endMode: "until", until: "2026-09-28")
        let dailyHits = expand(daily, from: compose(year: 2026, month: 9, day: 24), to: compose(year: 2026, month: 10, day: 5)).map { format($0.start, time: false) }
        check(dailyHits == ["2026-09-24", "2026-09-26", "2026-09-28"], "every two days until date")

        var monday = weekly
        monday.repeatRule = RepeatRule(type: "custom", interval: 1, unit: "week", weekdays: [1], endMode: "forever", until: nil)
        let mondayHits = expand(monday, from: compose(year: 2026, month: 9, day: 24), to: compose(year: 2026, month: 10, day: 6)).map { format($0.start, time: false) }
        check(mondayHits == ["2026-09-28", "2026-10-05"], "weekday filter skips the start Thursday")

        check(repeatSummary(RepeatRule.none(), start: start) == "不重复", "summary none")
        check(everyLabel(interval: 1, unitIndex: 1) == "每1周", "custom label")

        let raw = """
        {"schemaVersion":1,"app":"日程台","preferences":{"fontSize":18,"soundEnabled":false,"widgets":{"schedule":{"visible":true,"x":1,"y":2,"width":3,"height":4},"reminders":{"visible":false,"x":0,"y":0,"width":0,"height":0},"combined":{"visible":true,"x":0,"y":0,"width":0,"height":0}}},"events":[],"reminders":[{"id":"11111111-1111-1111-1111-111111111111","title":"买牛奶","notes":"全脂","due":null,"priority":2,"completed":false,"completedAt":null,"createdAt":"2026-09-24T00:00:00Z","updatedAt":"2026-09-24T00:00:00Z"}]}
        """.data(using: .utf8)!
        let decoded = try? Database.decode(raw)
        check(decoded?.preferences.fontSize == 18, "import keeps font size")
        check(decoded?.preferences.soundEnabled == false, "import keeps sound preference")
        check(decoded?.preferences.cardColor == Preferences.defaultCardColor, "import keeps default card color")
        check(decoded?.preferences.startColor == Preferences.defaultStartColor, "import keeps default start color")
        check(decoded?.preferences.endColor == Preferences.defaultEndColor, "import keeps default end color")
        check(decoded?.preferences.showCompletedReminders == true, "import shows completed reminders by default")
        check(decoded?.preferences.scheduleOnTop == false, "schedule stays off top by default")
        check(decoded?.preferences.remindersOnTop == false, "reminders stay off top by default")
        check(decoded?.preferences.combinedOnTop == false, "combined stays off top by default")
        check(decoded?.preferences.scrollSensitivity == 1, "scroll sensitivity defaults to low")
        check(decoded?.preferences.earlyReminder == true, "early reminder defaults to on")
        check(decoded?.reminders.first?.title == "买牛奶", "import keeps reminders")
        check(decoded?.reminders.first?.priority == 2, "import keeps priority")
        let tinted = """
        {"schemaVersion":1,"app":"日程台","preferences":{"fontSize":14,"soundEnabled":true,"cardColor":"#445566","startColor":"not-a-color","endColor":"#AABBCC","widgets":{"schedule":{"visible":true,"x":0,"y":0,"width":0,"height":0},"reminders":{"visible":true,"x":0,"y":0,"width":0,"height":0},"combined":{"visible":true,"x":0,"y":0,"width":0,"height":0}}}}
        """.data(using: .utf8)!
        let tintedDB = try? Database.decode(tinted)
        check(tintedDB?.preferences.cardColor == "#445566", "import keeps card color")
        check(tintedDB?.preferences.startColor == Preferences.defaultStartColor, "invalid start color falls back")
        check(tintedDB?.preferences.endColor == "#AABBCC", "import keeps end color")

        if failed > 0 {
            fputs("\(failed) failed\n", stderr)
            exit(1)
        }
        print("self-test passed")
    }
}

struct RepeatRule: Codable, Equatable {
    var type: String
    var interval: Int
    var unit: String
    var weekdays: [Int]
    var endMode: String
    var until: String?

    static func none() -> RepeatRule {
        RepeatRule(type: "none", interval: 1, unit: "week", weekdays: [], endMode: "forever", until: nil)
    }

    static func preset(_ type: String) -> RepeatRule {
        RepeatRule(type: type, interval: 1, unit: "week", weekdays: [], endMode: "forever", until: nil)
    }
}

struct ScheduleEvent: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var notes: String
    var allDay: Bool
    var start: String
    var end: String
    var repeatRule: RepeatRule
    var createdAt: String
    var updatedAt: String
    var excludedDates: [String]

    init(id: UUID, title: String, notes: String, allDay: Bool, start: String, end: String, repeatRule: RepeatRule, createdAt: String, updatedAt: String, excludedDates: [String] = []) {
        self.id = id
        self.title = title
        self.notes = notes
        self.allDay = allDay
        self.start = start
        self.end = end
        self.repeatRule = repeatRule
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.excludedDates = excludedDates
    }

    static func make(title: String, start: String, end: String, allDay: Bool = false, id: UUID = UUID()) -> ScheduleEvent {
        let stamp = Logic.nowStamp()
        return ScheduleEvent(id: id, title: title, notes: "", allDay: allDay, start: start, end: end, repeatRule: .none(), createdAt: stamp, updatedAt: stamp)
    }

    enum CodingKeys: String, CodingKey {
        case id, title, notes, allDay, start, end, repeatRule, createdAt, updatedAt, excludedDates
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = try box.decode(UUID.self, forKey: .id)
        title = try box.decode(String.self, forKey: .title)
        notes = try box.decodeIfPresent(String.self, forKey: .notes) ?? ""
        allDay = try box.decodeIfPresent(Bool.self, forKey: .allDay) ?? false
        start = try box.decode(String.self, forKey: .start)
        end = try box.decode(String.self, forKey: .end)
        repeatRule = try box.decodeIfPresent(RepeatRule.self, forKey: .repeatRule) ?? .none()
        createdAt = try box.decodeIfPresent(String.self, forKey: .createdAt) ?? Logic.nowStamp()
        updatedAt = try box.decodeIfPresent(String.self, forKey: .updatedAt) ?? createdAt
        excludedDates = try box.decodeIfPresent([String].self, forKey: .excludedDates) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(id, forKey: .id)
        try box.encode(title, forKey: .title)
        try box.encode(notes, forKey: .notes)
        try box.encode(allDay, forKey: .allDay)
        try box.encode(start, forKey: .start)
        try box.encode(end, forKey: .end)
        try box.encode(repeatRule, forKey: .repeatRule)
        try box.encode(createdAt, forKey: .createdAt)
        try box.encode(updatedAt, forKey: .updatedAt)
        try box.encode(excludedDates, forKey: .excludedDates)
    }
}

struct ReminderItem: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var notes: String
    var due: String?
    var priority: Int
    var completed: Bool
    var completedAt: String?
    var createdAt: String
    var updatedAt: String
}

struct WidgetFrame: Codable, Equatable {
    var visible: Bool
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    static func hidden() -> WidgetFrame {
        WidgetFrame(visible: false, x: 0, y: 0, width: 0, height: 0)
    }
}

struct WidgetPreferences: Codable, Equatable {
    var schedule: WidgetFrame
    var reminders: WidgetFrame
    var combined: WidgetFrame

    func frame(for kind: String) -> WidgetFrame {
        switch kind {
        case "reminders": return reminders
        case "combined": return combined
        default: return schedule
        }
    }

    mutating func setFrame(_ frame: WidgetFrame, for kind: String) {
        switch kind {
        case "reminders": reminders = frame
        case "combined": combined = frame
        default: schedule = frame
        }
    }
}

struct Preferences: Codable, Equatable {
    var fontSize: Double
    var soundEnabled: Bool
    var widgets: WidgetPreferences
    var cardColor: String
    var startColor: String
    var endColor: String
    var showCompletedReminders: Bool
    var scheduleOnTop: Bool
    var remindersOnTop: Bool
    var combinedOnTop: Bool
    var scrollSensitivity: Double
    var earlyReminder: Bool

    static let defaultCardColor = "#5A6874"
    static let defaultStartColor = "#9CE8B5"
    static let defaultEndColor = "#9E9E9E"

    static func initial() -> Preferences {
        Preferences(
            fontSize: 14,
            soundEnabled: true,
            widgets: WidgetPreferences(
                schedule: WidgetFrame(visible: false, x: 0, y: 0, width: 0, height: 0),
                reminders: WidgetFrame(visible: false, x: 0, y: 0, width: 0, height: 0),
                combined: WidgetFrame(visible: false, x: 0, y: 0, width: 0, height: 0)
            ),
            cardColor: defaultCardColor,
            startColor: defaultStartColor,
            endColor: defaultEndColor,
            showCompletedReminders: true,
            scheduleOnTop: false,
            remindersOnTop: false,
            combinedOnTop: false,
            scrollSensitivity: 1,
            earlyReminder: true
        )
    }

    init(fontSize: Double, soundEnabled: Bool, widgets: WidgetPreferences, cardColor: String, startColor: String, endColor: String, showCompletedReminders: Bool, scheduleOnTop: Bool, remindersOnTop: Bool, combinedOnTop: Bool, scrollSensitivity: Double, earlyReminder: Bool) {
        self.fontSize = fontSize
        self.soundEnabled = soundEnabled
        self.widgets = widgets
        self.cardColor = cardColor
        self.startColor = startColor
        self.endColor = endColor
        self.showCompletedReminders = showCompletedReminders
        self.scheduleOnTop = scheduleOnTop
        self.remindersOnTop = remindersOnTop
        self.combinedOnTop = combinedOnTop
        self.scrollSensitivity = scrollSensitivity
        self.earlyReminder = earlyReminder
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        fontSize = try box.decodeIfPresent(Double.self, forKey: .fontSize) ?? 14
        soundEnabled = try box.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? true
        widgets = try box.decodeIfPresent(WidgetPreferences.self, forKey: .widgets) ?? Preferences.initial().widgets
        cardColor = try box.decodeIfPresent(String.self, forKey: .cardColor) ?? Preferences.defaultCardColor
        startColor = try box.decodeIfPresent(String.self, forKey: .startColor) ?? Preferences.defaultStartColor
        endColor = try box.decodeIfPresent(String.self, forKey: .endColor) ?? Preferences.defaultEndColor
        showCompletedReminders = try box.decodeIfPresent(Bool.self, forKey: .showCompletedReminders) ?? true
        scheduleOnTop = try box.decodeIfPresent(Bool.self, forKey: .scheduleOnTop) ?? false
        remindersOnTop = try box.decodeIfPresent(Bool.self, forKey: .remindersOnTop) ?? false
        combinedOnTop = try box.decodeIfPresent(Bool.self, forKey: .combinedOnTop) ?? false
        scrollSensitivity = try box.decodeIfPresent(Double.self, forKey: .scrollSensitivity) ?? 1
        earlyReminder = try box.decodeIfPresent(Bool.self, forKey: .earlyReminder) ?? true
    }
}

struct NotificationState: Codable, Equatable {
    var fired: [String: String]
    var snoozed: [String: String]

    static func empty() -> NotificationState {
        NotificationState(fired: [:], snoozed: [:])
    }
}

struct Database: Codable, Equatable {
    var schemaVersion: Int
    var app: String
    var summary: String
    var preferences: Preferences
    var events: [ScheduleEvent]
    var reminders: [ReminderItem]
    var notificationState: NotificationState

    init(schemaVersion: Int, app: String, summary: String, preferences: Preferences, events: [ScheduleEvent], reminders: [ReminderItem], notificationState: NotificationState) {
        self.schemaVersion = schemaVersion
        self.app = app
        self.summary = summary
        self.preferences = preferences
        self.events = events
        self.reminders = reminders
        self.notificationState = notificationState
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try box.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Logic.schemaVersion
        app = try box.decodeIfPresent(String.self, forKey: .app) ?? Logic.appName
        summary = try box.decodeIfPresent(String.self, forKey: .summary) ?? ""
        preferences = try box.decodeIfPresent(Preferences.self, forKey: .preferences) ?? .initial()
        events = try box.decodeIfPresent([ScheduleEvent].self, forKey: .events) ?? []
        reminders = try box.decodeIfPresent([ReminderItem].self, forKey: .reminders) ?? []
        notificationState = try box.decodeIfPresent(NotificationState.self, forKey: .notificationState) ?? .empty()
    }

    static func empty() -> Database {
        Database(
            schemaVersion: Logic.schemaVersion,
            app: Logic.appName,
            summary: "macOS 与 Windows 通用 JSON 数据库，包含偏好设置、日程和提醒事项。",
            preferences: .initial(),
            events: [],
            reminders: [],
            notificationState: .empty()
        )
    }

    static func decode(_ data: Data) throws -> Database {
        var payload = data
        if payload.starts(with: [0xEF, 0xBB, 0xBF]) { payload = payload.dropFirst(3) }
        let decoded = try JSONDecoder().decode(Database.self, from: payload)
        return decoded.sanitized()
    }

    func encode() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    func sanitized() -> Database {
        var copy = self
        copy.schemaVersion = Logic.schemaVersion
        copy.app = Logic.appName
        if copy.summary.isEmpty {
            copy.summary = Database.empty().summary
        }
        copy.preferences.fontSize = min(22, max(12, copy.preferences.fontSize))
        copy.preferences.scrollSensitivity = min(5, max(1, copy.preferences.scrollSensitivity))
        copy.preferences.cardColor = Logic.hexColor(copy.preferences.cardColor) ?? Preferences.defaultCardColor
        copy.preferences.startColor = Logic.hexColor(copy.preferences.startColor) ?? Preferences.defaultStartColor
        copy.preferences.endColor = Logic.hexColor(copy.preferences.endColor) ?? Preferences.defaultEndColor
        copy.events = copy.events.compactMap { event in
            let title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, Logic.parse(event.start) != nil else { return nil }
            var clean = event
            clean.title = String(title.prefix(200))
            clean.notes = String(event.notes.prefix(5000))
            if Logic.parse(clean.end) == nil {
                clean.end = clean.allDay ? String(clean.start.prefix(10)) : Logic.format(Logic.defaultEnd(start: Logic.parse(clean.start)!, allDay: false), time: true)
            }
            return clean
        }
        copy.reminders = copy.reminders.compactMap { item in
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            var clean = item
            clean.title = String(title.prefix(200))
            clean.notes = String(item.notes.prefix(5000))
            clean.priority = min(3, max(0, item.priority))
            if let due = clean.due, Logic.parse(due) == nil { clean.due = nil }
            if !clean.completed { clean.completedAt = nil }
            return clean
        }
        return copy
    }
}

struct Occurrence: Identifiable {
    var id: String { Logic.occurrenceKey(kind: "event", id: event.id, start: start, allDay: event.allDay) }
    var event: ScheduleEvent
    var start: Date
    var end: Date
    var conflict: Bool
}

struct DayGroup: Identifiable {
    var id: String { Logic.format(date, time: false) }
    var date: Date
    var items: [Occurrence]
}

struct Notice: Identifiable {
    var id: String { key }
    var key: String
    var kind: String
    var title: String
    var notes: String
    var when: String
    var conflict: Bool
    var refID: UUID
}
