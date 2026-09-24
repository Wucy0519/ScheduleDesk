import Foundation

final class Store {
    private(set) var database: Database
    private(set) var dataPath: URL
    private let configPath: URL
    var onChange: (() -> Void)?

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("日程台", isDirectory: true)
        configPath = support.appendingPathComponent("config.json")
        let fallback = support.appendingPathComponent("日程台数据.json")
        dataPath = Store.readConfig(at: configPath) ?? fallback
        database = Store.readDatabase(at: dataPath) ?? .empty()
        try? FileManager.default.createDirectory(at: dataPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        persist()
        writeConfig()
    }

    func mutate(_ body: (inout Database) -> Void) {
        var copy = database
        body(&copy)
        database = copy.sanitized()
        persist()
        onChange?()
    }

    func upsertEvent(_ event: ScheduleEvent) {
        mutate { db in
            if let index = db.events.firstIndex(where: { $0.id == event.id }) {
                var copy = event
                copy.createdAt = db.events[index].createdAt
                copy.updatedAt = Logic.nowStamp()
                db.events[index] = copy
            } else {
                var copy = event
                copy.updatedAt = Logic.nowStamp()
                db.events.append(copy)
            }
        }
    }

    func deleteEvent(_ id: UUID) {
        mutate { $0.events.removeAll { $0.id == id } }
    }

    func excludeEventDay(_ id: UUID, day: Date) {
        mutate { db in
            guard let index = db.events.firstIndex(where: { $0.id == id }) else { return }
            let key = Logic.format(Logic.startOfDay(day), time: false)
            if !db.events[index].excludedDates.contains(key) {
                db.events[index].excludedDates.append(key)
            }
            db.events[index].updatedAt = Logic.nowStamp()
        }
    }

    func upsertReminder(_ item: ReminderItem) {
        mutate { db in
            if let index = db.reminders.firstIndex(where: { $0.id == item.id }) {
                var copy = item
                copy.createdAt = db.reminders[index].createdAt
                copy.updatedAt = Logic.nowStamp()
                db.reminders[index] = copy
            } else {
                var copy = item
                copy.updatedAt = Logic.nowStamp()
                db.reminders.append(copy)
            }
        }
    }

    func deleteReminder(_ id: UUID) {
        mutate { $0.reminders.removeAll { $0.id == id } }
    }

    func toggleReminder(_ id: UUID) {
        mutate { db in
            guard let index = db.reminders.firstIndex(where: { $0.id == id }) else { return }
            db.reminders[index].completed.toggle()
            db.reminders[index].completedAt = db.reminders[index].completed ? Logic.nowStamp() : nil
            db.reminders[index].updatedAt = Logic.nowStamp()
        }
    }

    func updatePreferences(_ body: (inout Preferences) -> Void) {
        mutate { body(&$0.preferences) }
    }

    func markFired(_ keys: [String]) {
        mutate { db in
            let stamp = Logic.nowStamp()
            for key in keys {
                db.notificationState.fired[key] = stamp
                db.notificationState.snoozed[key] = nil
            }
            let cutoff = Date().addingTimeInterval(-14 * 86_400)
            let formatter = ISO8601DateFormatter()
            db.notificationState.fired = db.notificationState.fired.filter { _, value in
                guard let date = formatter.date(from: value) else { return false }
                return date > cutoff
            }
        }
    }

    func snooze(_ keys: [String], minutes: Int) {
        mutate { db in
            let until = Logic.nowStamp(Date().addingTimeInterval(TimeInterval(minutes * 60)))
            for key in keys {
                db.notificationState.fired[key] = nil
                db.notificationState.snoozed[key] = until
            }
        }
    }

    @discardableResult
    func replace(with raw: Data) -> String? {
        do {
            let incoming = try Database.decode(raw)
            database = incoming
            persist()
            onChange?()
            return nil
        } catch {
            return "无法读取这个数据库：\(error.localizedDescription)"
        }
    }

    func useDatabase(at url: URL, createIfMissing: Bool) -> String? {
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                database = try Database.decode(Data(contentsOf: url))
            } catch {
                return "这个文件不是日程台数据库。"
            }
        } else if createIfMissing {
            database = .empty()
        } else {
            return "找不到数据库文件。"
        }
        dataPath = url
        persist()
        writeConfig()
        onChange?()
        return nil
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: dataPath.deletingLastPathComponent(), withIntermediateDirectories: true)
            try database.encode().write(to: dataPath, options: .atomic)
        } catch {
            fputs("保存数据库失败：\(error)\n", stderr)
        }
    }

    private func writeConfig() {
        let payload = try? JSONSerialization.data(withJSONObject: ["dataPath": dataPath.path], options: [.prettyPrinted])
        try? FileManager.default.createDirectory(at: configPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? payload?.write(to: configPath, options: .atomic)
    }

    private static func readConfig(at url: URL) -> URL? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let path = json["dataPath"] as? String,
              !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    private static func readDatabase(at url: URL) -> Database? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let database = try? Database.decode(data) { return database }
        let backup = url.deletingLastPathComponent().appendingPathComponent("日程台数据.损坏-\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.copyItem(at: url, to: backup)
        return nil
    }
}
