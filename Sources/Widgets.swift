import SwiftUI

struct ScheduleWidget: View {
    @ObservedObject var store: Store
    var onCreate: () -> Void
    var onOpen: (UUID) -> Void
    @State private var selected: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("日程", tint: WidgetChrome.green, label: "创建新的日程", action: onCreate)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(groups) { group in
                        Text(Logic.dayHeading(group.date, today: Logic.startOfDay(Date())))
                            .font(.system(size: font + 1, weight: .semibold))
                            .foregroundStyle(group.id == Logic.format(Date(), time: false) ? Color.white : Color.secondary)
                        if group.items.isEmpty {
                            Text("没有日程")
                                .font(.system(size: font - 1))
                                .foregroundStyle(.tertiary)
                                .padding(.bottom, 4)
                        }
                        ForEach(group.items) { item in
                            eventRow(item)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .widgetSurface(font: font)
        .focusable()
        .focused($focused)
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.return) { openSelected(); return .handled }
    }

    private var groups: [DayGroup] { Logic.agenda(events: store.database.events, now: Date()) }
    private var font: Double { store.database.preferences.fontSize }
    private var keys: [String] { groups.flatMap { $0.items.map(\.id) } }

    private func eventRow(_ item: Occurrence) -> some View {
        let time = Logic.timeLabel(item)
        let past = item.end <= Date()
        return Button {
            if selected == item.id { onOpen(item.event.id) } else { selected = item.id; focused = true }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(time.start).font(.system(size: font - 1, weight: .semibold))
                    if !time.end.isEmpty {
                        Text(time.end).font(.system(size: max(11, font - 3)))
                    }
                }
                .foregroundStyle(WidgetChrome.green)
                .frame(width: 64, alignment: .trailing)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.event.title)
                        .font(.system(size: font, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    if item.conflict {
                        Text("有冲突")
                            .font(.system(size: max(11, font - 2), weight: .semibold))
                            .foregroundStyle(WidgetChrome.conflict)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
            .background(selected == item.id ? Color.white.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
            .opacity(past ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.event.title)，\(time.start) \(time.end)\(item.conflict ? "，有冲突" : "")")
    }

    private func move(_ delta: Int) {
        focused = true
        let items = keys
        guard !items.isEmpty else { return }
        let index = items.firstIndex(of: selected ?? "") ?? (delta > 0 ? -1 : 0)
        selected = items[min(max(index + delta, 0), items.count - 1)]
    }

    private func openSelected() {
        guard let selected, let item = groups.flatMap(\.items).first(where: { $0.id == selected }) else { return }
        onOpen(item.event.id)
    }
}

struct ReminderWidget: View {
    @ObservedObject var store: Store
    var onCreate: () -> Void
    var onOpen: (UUID) -> Void
    @State private var selected: UUID?
    @FocusState private var focused: Bool

    var body: some View {
        let split = Logic.splitReminders(store.database.reminders, now: Date())
        VStack(alignment: .leading, spacing: 0) {
            header("提醒事项", tint: WidgetChrome.purple, label: "创建新的提醒事项", action: onCreate)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if split.open.isEmpty && split.done.isEmpty {
                        Text("没有提醒事项")
                            .font(.system(size: font - 1))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 16)
                    }
                    ForEach(split.open) { item in
                        reminderRow(item)
                    }
                    if !split.done.isEmpty {
                        Text("已完成")
                            .font(.system(size: font - 1, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                        ForEach(split.done) { item in
                            reminderRow(item)
                        }
                    }
                }
                .padding(.bottom, 16)
            }
        }
        .widgetSurface(font: font)
        .focusable()
        .focused($focused)
        .onKeyPress(.downArrow) { move(1, ids: split.open.map(\.id) + split.done.map(\.id)); return .handled }
        .onKeyPress(.upArrow) { move(-1, ids: split.open.map(\.id) + split.done.map(\.id)); return .handled }
        .onKeyPress(.return) { if let selected { onOpen(selected) }; return .handled }
        .onKeyPress(.space) {
            if let selected { store.toggleReminder(selected) }
            return .handled
        }
    }

    private var font: Double { store.database.preferences.fontSize }

    private func reminderRow(_ item: ReminderItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                store.toggleReminder(item.id)
            } label: {
                Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: font + 6))
                    .foregroundStyle(item.completed ? WidgetChrome.purple : Color.white.opacity(0.45))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.completed ? "标为未完成" : "标为已完成")
            Button {
                if selected == item.id { onOpen(item.id) } else { selected = item.id; focused = true }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.title)
                            .font(.system(size: font, weight: .medium))
                            .strikethrough(item.completed)
                            .foregroundStyle(item.completed ? Color.secondary : Color.white)
                            .lineLimit(2)
                        if item.priority > 0 {
                            Text(["", "低", "中", "高"][item.priority])
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(priorityColor(item.priority))
                        }
                    }
                    if let due = item.due.flatMap(Logic.parse) {
                        Text(Logic.dueLabel(due, now: Date()))
                            .font(.system(size: max(11, font - 2)))
                            .foregroundStyle(!item.completed && due < Date() ? WidgetChrome.conflict : Color.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 16)
        .background(selected == item.id ? Color.white.opacity(0.08) : Color.clear)
    }

    private func move(_ delta: Int, ids: [UUID]) {
        focused = true
        guard !ids.isEmpty else { return }
        let index = ids.firstIndex(of: selected ?? UUID()) ?? (delta > 0 ? -1 : 0)
        selected = ids[min(max(index + delta, 0), ids.count - 1)]
    }

    private func priorityColor(_ priority: Int) -> Color {
        switch priority {
        case 3: return WidgetChrome.conflict
        case 2: return .orange
        default: return .blue
        }
    }
}

struct CombinedWidget: View {
    @ObservedObject var store: Store
    var onCreateEvent: () -> Void
    var onCreateReminder: () -> Void
    var onOpenEvent: (UUID) -> Void
    var onOpenReminder: (UUID) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ReminderWidget(store: store, onCreate: onCreateReminder, onOpen: onOpenReminder)
            Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1)
            ScheduleWidget(store: store, onCreate: onCreateEvent, onOpen: onOpenEvent)
        }
        .background(WidgetChrome.background)
    }
}

enum WidgetChrome {
    static let background = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let green = Color(red: 0.61, green: 0.91, blue: 0.71)
    static let purple = Color(red: 0.84, green: 0.71, blue: 0.97)
    static let conflict = Color(red: 1, green: 0.27, blue: 0.23)
}

extension View {
    func widgetSurface(font: Double) -> some View {
        self.background(WidgetChrome.background)
            .environment(\.sizeCategory, .large)
    }

    func header(_ title: String, tint: Color, label: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title).font(.system(size: 17, weight: .semibold))
            Spacer()
            Button(action: action) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(tint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }
}
