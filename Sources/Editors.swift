import SwiftUI

struct EventEditor: View {
    @ObservedObject var store: Store
    var existingID: UUID?
    var onClose: () -> Void

    @State private var title = ""
    @State private var notes = ""
    @State private var allDay = false
    @State private var endLinked = true
    @State private var rule = RepeatRule.none()
    @State private var custom = RepeatRule.customDraft(from: .none(), start: Date())
    @State private var page = Page.form
    @State private var startYear = 2026
    @State private var startMonth = 1
    @State private var startDay = 1
    @State private var startHour = 9
    @State private var startMinute = 0
    @State private var endYear = 2026
    @State private var endMonth = 1
    @State private var endDay = 1
    @State private var endHour = 10
    @State private var endMinute = 0
    @State private var untilYear = 2026
    @State private var untilMonth = 1
    @State private var untilDay = 1
    @State private var createdAt = ""
    @State private var confirmDelete = false
    @State private var repeatHighlight = 0
    @State private var weekdayHighlight = 0
    @State private var showUntilChoices = false
    @FocusState private var repeatFocused: Bool
    @FocusState private var weekdayFocused: Bool

    private enum Page { case form, repeats, custom }

    var body: some View {
        ZStack {
            (page == .custom ? Color.black : WidgetChrome.background).ignoresSafeArea()
            switch page {
            case .form: form
            case .repeats: repeatPicker
            case .custom: customPicker
            }
        }
        .frame(minWidth: 420, minHeight: 640)
        .preferredColorScheme(.dark)
        .onAppear(perform: load)
        .alert("删除这个日程？", isPresented: $confirmDelete) {
            Button("删除", role: .destructive) {
                if let existingID { store.deleteEvent(existingID); onClose() }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private var form: some View {
        VStack(spacing: 0) {
            sheetHeader(title: existingID == nil ? "新建日程" : "编辑日程", saveTitle: "添加", enabled: canSave, save: save)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TextField("日程名称", text: $title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 22, weight: .semibold))
                    TextField("备注", text: $notes, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(3...6)
                        .foregroundStyle(.secondary)
                    toggleRow("全天", isOn: $allDay)
                    Button {
                        page = .repeats
                    } label: {
                        row(label: "重复", value: Logic.repeatSummary(rule, start: startDate))
                    }
                    .buttonStyle(.plain)
                    if !conflictTitles.isEmpty {
                        Text("有冲突")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(WidgetChrome.conflict)
                        Text(conflictTitles.joined(separator: "、"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    if !endIsValid {
                        Text("结束时间需要晚于开始时间")
                            .foregroundStyle(WidgetChrome.conflict)
                            .font(.system(size: 12))
                    }
                    groupLabel("开始")
                    DateWheels(year: $startYear, month: $startMonth, day: $startDay, hour: $startHour, minute: $startMinute, showsTime: !allDay) {
                        if endLinked { applyLinkedEnd() }
                    }
                    groupLabel(endLinked && !allDay ? "结束 · 未指定时为开始后 1 小时" : "结束")
                    DateWheels(year: $endYear, month: $endMonth, day: $endDay, hour: $endHour, minute: $endMinute, showsTime: !allDay) {
                        endLinked = false
                    }
                    if existingID != nil {
                        Button("删除日程") { confirmDelete = true }
                            .foregroundStyle(WidgetChrome.conflict)
                            .buttonStyle(.plain)
                            .padding(.top, 8)
                    }
                }
                .padding(20)
            }
        }
    }

    private var repeatPicker: some View {
        VStack(spacing: 0) {
            sheetHeader(title: "重复", saveTitle: "完成", enabled: true) { page = .form }
            VStack(spacing: 0) {
                ForEach(Array(repeatOptions.enumerated()), id: \.offset) { index, option in
                    Button {
                        repeatHighlight = index
                        repeatFocused = true
                        if option == "自定义" {
                            custom = Logic.customDraft(from: rule, start: startDate)
                            loadUntil()
                            page = .custom
                        } else {
                            rule = RepeatRule.preset(["不重复", "每天", "每周", "每月", "每年"][index] == "不重复" ? "none" : ["none", "daily", "weekly", "monthly", "yearly"][index])
                            page = .form
                        }
                    } label: {
                        HStack {
                            Text(option)
                            Spacer()
                            if repeatOptions[index] != "自定义" && rule.type == ["none", "daily", "weekly", "monthly", "yearly"][index] {
                                Image(systemName: "checkmark").foregroundStyle(Color(red: 1, green: 0.42, blue: 0.24))
                            }
                            if option == "自定义" { Image(systemName: "chevron.right").foregroundStyle(.secondary) }
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 44)
                        .background(repeatHighlight == index ? Color.white.opacity(0.08) : Color.clear)
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, 16)
                }
            }
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            .padding(16)
            Spacer()
        }
        .focusable()
        .focused($repeatFocused)
        .onAppear { repeatFocused = true }
        .onKeyPress(.downArrow) { repeatHighlight = min(repeatHighlight + 1, repeatOptions.count - 1); return .handled }
        .onKeyPress(.upArrow) { repeatHighlight = max(repeatHighlight - 1, 0); return .handled }
        .onKeyPress(.return) { activateRepeat(); return .handled }
    }

    private var customPicker: some View {
        VStack(spacing: 0) {
            HStack {
                Button { page = .repeats } label: { Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)) }
                    .buttonStyle(.plain)
                Spacer()
                Text("自定义").font(.system(size: 17, weight: .semibold))
                Spacer()
                Button { confirmCustom() } label: { Image(systemName: "checkmark").font(.system(size: 16, weight: .bold)) }
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .frame(height: 52)
            ScrollView {
                VStack(spacing: 14) {
                    VStack(spacing: 0) {
                        HStack {
                            Text("重复类型")
                            Spacer()
                            Text(Logic.everyLabel(interval: custom.interval, unitIndex: unitIndex))
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.up").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 46)
                        WheelBank(columns: [
                            .init(id: "n", title: "", values: Array(1...99), loop: true, label: { "\($0)" }, value: $customInterval),
                            .init(id: "u", title: "", values: Array(0...3), loop: false, label: { Logic.unitLabels[$0] }, value: $unitIndex)
                        ], onInteract: {})
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                    }
                    .background(Color(red: 0.11, green: 0.11, blue: 0.12), in: RoundedRectangle(cornerRadius: 16))

                    if custom.unit == "week" {
                        VStack(spacing: 0) {
                            ForEach(0..<7, id: \.self) { day in
                                Button {
                                    weekdayHighlight = day
                                    weekdayFocused = true
                                    toggleWeekday(day)
                                } label: {
                                    HStack {
                                        Text(Logic.weekdayLong[day])
                                        Spacer()
                                        ZStack {
                                            Circle().strokeBorder(custom.weekdays.contains(day) ? Color(red: 1, green: 0.42, blue: 0.24) : Color.white.opacity(0.35), lineWidth: 1.5)
                                            if custom.weekdays.contains(day) {
                                                Circle().fill(Color(red: 1, green: 0.42, blue: 0.24))
                                                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                                            }
                                        }
                                        .frame(width: 22, height: 22)
                                    }
                                    .padding(.horizontal, 16)
                                    .frame(height: 46)
                                    .background(weekdayHighlight == day ? Color.white.opacity(0.06) : Color.clear)
                                }
                                .buttonStyle(.plain)
                                if day < 6 { Divider().padding(.leading, 16) }
                            }
                        }
                        .background(Color(red: 0.11, green: 0.11, blue: 0.12), in: RoundedRectangle(cornerRadius: 16))
                        .focusable()
                        .focused($weekdayFocused)
                        .onKeyPress(.downArrow) { weekdayHighlight = min(6, weekdayHighlight + 1); return .handled }
                        .onKeyPress(.upArrow) { weekdayHighlight = max(0, weekdayHighlight - 1); return .handled }
                        .onKeyPress(.space) { toggleWeekday(weekdayHighlight); return .handled }
                        if custom.weekdays.isEmpty {
                            Text("请至少选择一天").foregroundStyle(WidgetChrome.conflict).font(.system(size: 12))
                        }
                    }

                    VStack(spacing: 0) {
                        Button { showUntilChoices.toggle() } label: {
                            HStack {
                                Text("有效日期")
                                Spacer()
                                Text(untilText).foregroundStyle(.secondary)
                                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 46)
                        }
                        .buttonStyle(.plain)
                        if showUntilChoices {
                            Divider()
                            choice("一直", selected: custom.endMode != "until") {
                                custom.endMode = "forever"
                                custom.until = nil
                                showUntilChoices = false
                            }
                            choice("指定日期", selected: custom.endMode == "until") {
                                custom.endMode = "until"
                                if custom.until == nil { custom.until = Logic.format(Logic.addDays(startDate, 365), time: false) }
                                loadUntil()
                            }
                        }
                        if custom.endMode == "until" {
                            DateWheels(year: $untilYear, month: $untilMonth, day: $untilDay, hour: .constant(0), minute: .constant(0), showsTime: false) {
                                custom.until = Logic.format(Logic.compose(year: untilYear, month: untilMonth, day: untilDay), time: false)
                            }
                            .padding(.horizontal, 8)
                            .padding(.bottom, 8)
                        }
                    }
                    .background(Color(red: 0.11, green: 0.11, blue: 0.12), in: RoundedRectangle(cornerRadius: 16))
                }
                .padding(16)
            }
        }
    }

    private var repeatOptions: [String] { ["不重复", "每天", "每周", "每月", "每年", "自定义"] }
    private var startDate: Date { Logic.compose(year: startYear, month: startMonth, day: startDay, hour: allDay ? 0 : startHour, minute: allDay ? 0 : startMinute) }
    private var endDate: Date { Logic.compose(year: endYear, month: endMonth, day: endDay, hour: allDay ? 0 : endHour, minute: allDay ? 0 : endMinute) }
    private var endIsValid: Bool { allDay ? Logic.startOfDay(endDate) >= Logic.startOfDay(startDate) : endDate > startDate }
    private var canSave: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && endIsValid }
    private var untilText: String {
        guard custom.endMode == "until" else { return "一直" }
        return "\(untilYear)年\(untilMonth)月\(untilDay)日"
    }

    private var customInterval: Binding<Int> {
        Binding(get: { custom.interval }, set: { custom.interval = $0 })
    }

    private var unitIndex: Binding<Int> {
        Binding(
            get: { Logic.units.firstIndex(of: custom.unit) ?? 1 },
            set: { custom.unit = Logic.units[min(max($0, 0), 3)] }
        )
    }

    private var conflictTitles: [String] {
        guard canSave else { return [] }
        return Logic.conflicts(for: draftEvent(), among: store.database.events)
    }

    private func load() {
        guard createdAt.isEmpty else { return }
        if let existingID, let event = store.database.events.first(where: { $0.id == existingID }) {
            title = event.title
            notes = event.notes
            allDay = event.allDay
            rule = event.repeatRule
            createdAt = event.createdAt
            endLinked = false
            apply(event.start, toStart: true)
            apply(event.end, toStart: false)
        } else {
            let start = Logic.nextHour()
            let end = Logic.defaultEnd(start: start, allDay: false)
            apply(Logic.format(start, time: true), toStart: true)
            apply(Logic.format(end, time: true), toStart: false)
            createdAt = Logic.nowStamp()
            endLinked = true
        }
        loadUntil()
    }

    private func apply(_ raw: String, toStart: Bool) {
        let date = Logic.parse(raw) ?? Date()
        if toStart {
            startYear = Logic.component(date, .year)
            startMonth = Logic.component(date, .month)
            startDay = Logic.component(date, .day)
            startHour = Logic.component(date, .hour)
            startMinute = Logic.component(date, .minute)
        } else {
            endYear = Logic.component(date, .year)
            endMonth = Logic.component(date, .month)
            endDay = Logic.component(date, .day)
            endHour = Logic.component(date, .hour)
            endMinute = Logic.component(date, .minute)
        }
    }

    private func applyLinkedEnd() {
        let end = Logic.defaultEnd(start: startDate, allDay: allDay)
        endYear = Logic.component(end, .year)
        endMonth = Logic.component(end, .month)
        endDay = Logic.component(end, .day)
        if !allDay {
            endHour = Logic.component(end, .hour)
            endMinute = Logic.component(end, .minute)
        }
    }

    private func loadUntil() {
        let date = custom.until.flatMap(Logic.parse) ?? Logic.addDays(startDate, 365)
        untilYear = Logic.component(date, .year)
        untilMonth = Logic.component(date, .month)
        untilDay = Logic.component(date, .day)
    }

    private func draftEvent() -> ScheduleEvent {
        ScheduleEvent(
            id: existingID ?? UUID(),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            allDay: allDay,
            start: Logic.format(startDate, time: !allDay),
            end: Logic.format(allDay ? Logic.startOfDay(endDate) : endDate, time: !allDay),
            repeatRule: rule,
            createdAt: createdAt,
            updatedAt: Logic.nowStamp()
        )
    }

    private func save() {
        guard canSave else { return }
        var event = draftEvent()
        if existingID == nil { event.id = UUID() }
        store.upsertEvent(event)
        onClose()
    }

    private func confirmCustom() {
        if custom.unit == "week" && custom.weekdays.isEmpty { return }
        custom.interval = min(99, max(1, custom.interval))
        if custom.endMode == "until" {
            custom.until = Logic.format(Logic.compose(year: untilYear, month: untilMonth, day: untilDay), time: false)
        } else {
            custom.until = nil
            custom.endMode = "forever"
        }
        custom.type = "custom"
        rule = custom
        page = .form
    }

    private func toggleWeekday(_ day: Int) {
        if custom.weekdays.contains(day) {
            custom.weekdays.removeAll { $0 == day }
        } else {
            custom.weekdays.append(day)
            custom.weekdays.sort()
        }
    }

    private func activateRepeat() {
        let option = repeatOptions[repeatHighlight]
        if option == "自定义" {
            custom = Logic.customDraft(from: rule, start: startDate)
            loadUntil()
            page = .custom
        } else {
            rule = RepeatRule.preset(["none", "daily", "weekly", "monthly", "yearly"][repeatHighlight])
            page = .form
        }
    }

    private func choice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if selected { Image(systemName: "checkmark").foregroundStyle(Color(red: 1, green: 0.42, blue: 0.24)) }
            }
            .padding(.horizontal, 16)
            .frame(height: 40)
        }
        .buttonStyle(.plain)
    }

    private func groupLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
    }

    private func row(label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.trailing)
            Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }

    private func toggleRow(_ label: String, isOn: Binding<Bool>) -> some View {
        Toggle(label, isOn: isOn)
            .toggleStyle(.switch)
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }

    private func sheetHeader(title: String, saveTitle: String, enabled: Bool, save: @escaping () -> Void) -> some View {
        HStack {
            Button("取消", action: onClose).keyboardShortcut(.cancelAction)
            Spacer()
            Text(title).font(.system(size: 15, weight: .semibold))
            Spacer()
            Button(saveTitle, action: save).disabled(!enabled).keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }
}

struct ReminderEditor: View {
    @ObservedObject var store: Store
    var existingID: UUID?
    var onClose: () -> Void
    @State private var title = ""
    @State private var notes = ""
    @State private var hasDue = false
    @State private var priority = 0
    @State private var completed = false
    @State private var completedAt: String?
    @State private var createdAt = ""
    @State private var year = 2026
    @State private var month = 1
    @State private var day = 1
    @State private var hour = 9
    @State private var minute = 0
    @State private var confirmDelete = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("取消", action: onClose).keyboardShortcut(.cancelAction)
                Spacer()
                Text(existingID == nil ? "新建提醒事项" : "编辑提醒事项").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("添加", action: save).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TextField("事项名称", text: $title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 22, weight: .semibold))
                    TextField("备注", text: $notes, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(3...6)
                        .foregroundStyle(.secondary)
                    Toggle("提醒时间", isOn: $hasDue)
                        .toggleStyle(.switch)
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                    if hasDue {
                        DateWheels(year: $year, month: $month, day: $day, hour: $hour, minute: $minute, showsTime: true, onInteract: {})
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("优先级").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                        Picker("优先级", selection: $priority) {
                            Text("无").tag(0)
                            Text("低").tag(1)
                            Text("中").tag(2)
                            Text("高").tag(3)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    if existingID != nil {
                        Button("删除提醒事项") { confirmDelete = true }
                            .foregroundStyle(WidgetChrome.conflict)
                            .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
        }
        .background(WidgetChrome.background)
        .preferredColorScheme(.dark)
        .onAppear(perform: load)
        .alert("删除这个提醒事项？", isPresented: $confirmDelete) {
            Button("删除", role: .destructive) {
                if let existingID { store.deleteReminder(existingID); onClose() }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private func load() {
        guard createdAt.isEmpty else { return }
        if let existingID, let item = store.database.reminders.first(where: { $0.id == existingID }) {
            title = item.title
            notes = item.notes
            priority = item.priority
            completed = item.completed
            completedAt = item.completedAt
            createdAt = item.createdAt
            if let due = item.due.flatMap(Logic.parse) {
                hasDue = true
                year = Logic.component(due, .year)
                month = Logic.component(due, .month)
                day = Logic.component(due, .day)
                hour = Logic.component(due, .hour)
                minute = Logic.component(due, .minute)
            }
        } else {
            createdAt = Logic.nowStamp()
            let due = Logic.nextHour()
            year = Logic.component(due, .year)
            month = Logic.component(due, .month)
            day = Logic.component(due, .day)
            hour = Logic.component(due, .hour)
            minute = Logic.component(due, .minute)
        }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let due = hasDue ? Logic.format(Logic.compose(year: year, month: month, day: day, hour: hour, minute: minute), time: true) : nil
        store.upsertReminder(ReminderItem(
            id: existingID ?? UUID(),
            title: trimmed,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            due: due,
            priority: priority,
            completed: completed,
            completedAt: completedAt,
            createdAt: createdAt,
            updatedAt: Logic.nowStamp()
        ))
        onClose()
    }
}

struct NoticePanel: View {
    @ObservedObject var store: Store
    var notices: [Notice]
    var onClose: () -> Void
    var onSnooze: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(notices.contains(where: { $0.kind == "event" }) ? "日程到点" : "提醒事项").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            ForEach(notices) { notice in
                VStack(alignment: .leading, spacing: 4) {
                    Text(notice.when).font(.system(size: 13, weight: .semibold)).foregroundStyle(notice.kind == "event" ? WidgetChrome.green : WidgetChrome.purple)
                    Text(notice.title).font(.system(size: 18, weight: .semibold))
                    if !notice.notes.isEmpty {
                        Text(notice.notes).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(3)
                    }
                    if notice.conflict {
                        Text("有冲突").font(.system(size: 13, weight: .semibold)).foregroundStyle(WidgetChrome.conflict)
                    }
                }
            }
            Toggle("播放声音", isOn: sound)
                .toggleStyle(.switch)
            HStack {
                Button("知道了", action: onClose).keyboardShortcut(.defaultAction)
                Spacer()
                Button("5 分钟后", action: onSnooze)
            }
        }
        .padding(18)
        .frame(width: 340)
        .background(WidgetChrome.background)
        .preferredColorScheme(.dark)
    }

    private var sound: Binding<Bool> {
        Binding(
            get: { store.database.preferences.soundEnabled },
            set: { value in store.updatePreferences { $0.soundEnabled = value } }
        )
    }
}
