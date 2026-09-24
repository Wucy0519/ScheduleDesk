import AppKit
import UniformTypeIdentifiers

@main
enum ScheduleDeskMain {
    static func main() {
        if CommandLine.arguments.contains("--self-test") {
            Logic.runSelfTest()
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private let store = Store()
    private var widgets: [String: NSWindow] = [:]
    private var shownWidgets: Set<String> = []
    private var editors: [NSObject] = []
    private var lastOpen: [String: Date] = [:]
    private var settings: SettingsWindowController?
    private var notice: NoticeWindow?
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var pendingNotices: [Notice] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.onChange = { [weak self] in
            self?.syncWidgets()
            self?.settings?.reload()
        }
        ensureDefaultFrames()
        configureMenu()
        configureStatusItem()
        syncWidgets()
        armTimer()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "日程台"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(showItem("显示日程", "schedule"))
        menu.addItem(showItem("显示提醒事项", "reminders"))
        menu.addItem(showItem("显示综合组件", "combined"))
        menu.addItem(.separator())
        menu.addItem(withTitle: "新建日程", action: #selector(newEvent), keyEquivalent: "n").target = self
        menu.addItem(withTitle: "新建提醒事项", action: #selector(newReminder), keyEquivalent: "N").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出日程台", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func statusClicked() {
        openSettings()
    }

    private func configureMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.delegate = self
        appMenu.addItem(withTitle: "关于日程台", action: #selector(openSettings), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(showItem("显示日程", "schedule"))
        appMenu.addItem(showItem("显示提醒事项", "reminders"))
        appMenu.addItem(showItem("显示综合组件", "combined"))
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出日程台", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let fileItem = NSMenuItem()
        let file = NSMenu(title: "文件")
        file.addItem(withTitle: "新建日程", action: #selector(newEvent), keyEquivalent: "n").target = self
        file.addItem(withTitle: "新建提醒事项", action: #selector(newReminder), keyEquivalent: "N").target = self
        fileItem.submenu = file
        main.addItem(fileItem)
        NSApp.mainMenu = main
    }

    private func ensureDefaultFrames() {
        guard let screen = NSScreen.main?.visibleFrame else { return }
        let widgets = store.database.preferences.widgets
        let missing = ["schedule", "reminders", "combined"].filter { widgets.frame(for: $0).visible && widgets.frame(for: $0).width == 0 }
        guard !missing.isEmpty else { return }
        store.updatePreferences { prefs in
            for kind in missing {
                var frame = Self.defaultWidgetFrame(kind, screen: screen)
                frame.visible = true
                prefs.widgets.setFrame(frame, for: kind)
            }
        }
    }

    private static func defaultWidgetFrame(_ kind: String, screen: NSRect) -> WidgetFrame {
        let top = screen.maxY
        switch kind {
        case "reminders":
            return WidgetFrame(visible: false, x: screen.minX + 360, y: top - 560, width: 320, height: 520)
        case "combined":
            let combinedX = screen.minX + 696
            if combinedX + 660 < screen.maxX {
                return WidgetFrame(visible: false, x: combinedX, y: top - 560, width: 660, height: 520)
            }
            return WidgetFrame(visible: false, x: screen.minX + 24, y: top - 1100, width: min(660, screen.width - 48), height: 520)
        default:
            return WidgetFrame(visible: false, x: screen.minX + 24, y: top - 560, width: 320, height: 520)
        }
    }

    private static func widgetIsOnTop(_ kind: String, prefs: Preferences) -> Bool {
        switch kind {
        case "reminders": return prefs.remindersOnTop
        case "combined": return prefs.combinedOnTop
        default: return prefs.scheduleOnTop
        }
    }

    private func syncWidgets() {
        for kind in ["schedule", "reminders", "combined"] {
            let frame = store.database.preferences.widgets.frame(for: kind)
            if frame.visible {
                if frame.width == 0, let screen = NSScreen.main?.visibleFrame {
                    store.updatePreferences { prefs in
                        var placed = Self.defaultWidgetFrame(kind, screen: screen)
                        placed.visible = true
                        prefs.widgets.setFrame(placed, for: kind)
                    }
                }
                if widgets[kind] == nil { widgets[kind] = makeWidget(kind) }
                widgets[kind]?.level = Self.widgetIsOnTop(kind, prefs: store.database.preferences) ? .floating : .normal
                place(widgets[kind], kind: kind)
                (widgets[kind]?.contentView as? Reloading)?.reload()
            } else {
                widgets[kind]?.close()
                widgets[kind] = nil
                shownWidgets.remove(kind)
            }
        }
    }

    private func makeWidget(_ kind: String) -> NSWindow {
        let view: NSView
        switch kind {
        case "reminders":
            view = ReminderWidgetView(store: store, pinKind: "reminders", onCreate: { [weak self] in self?.openReminder(nil) }, onOpen: { [weak self] id in self?.openReminder(id) })
        case "combined":
            view = CombinedWidgetView(store: store, onCreateEvent: { [weak self] in self?.openEvent(nil) }, onCreateReminder: { [weak self] in self?.openReminder(nil) }, onOpenEvent: { [weak self] id, day in self?.openEvent(id, occurrence: day) }, onOpenReminder: { [weak self] id in self?.openReminder(id) })
        default:
            view = ScheduleWidgetView(store: store, pinKind: "schedule", onCreate: { [weak self] in self?.openEvent(nil) }, onOpen: { [weak self] id, day in self?.openEvent(id, occurrence: day) })
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: kind == "combined" ? 660 : 320, height: 520), styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = kind == "reminders" ? "提醒事项" : kind == "combined" ? "综合" : "日程"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.level = .normal
        window.collectionBehavior = [.managed]
        window.minSize = NSSize(width: kind == "combined" ? 560 : 280, height: 320)
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Chrome.background
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.delegate = self
        window.identifier = NSUserInterfaceItemIdentifier(kind)
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        return window
    }

    private func place(_ window: NSWindow?, kind: String) {
        guard let window else { return }
        let frame = store.database.preferences.widgets.frame(for: kind)
        let rect = clamped(NSRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height))
        if window.frame != rect { window.setFrame(rect, display: true) }
        if !shownWidgets.contains(kind) || (window.isOnActiveSpace && !window.isVisible) {
            window.orderFrontRegardless()
            shownWidgets.insert(kind)
        }
    }

    func windowDidMove(_ notification: Notification) { saveFrame(notification) }
    func windowDidResize(_ notification: Notification) { saveFrame(notification) }

    private func saveFrame(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, let kind = window.identifier?.rawValue, widgets[kind] === window else { return }
        let frame = window.frame
        store.onChange = nil
        store.updatePreferences { prefs in
            var current = prefs.widgets.frame(for: kind)
            current.x = frame.origin.x
            current.y = frame.origin.y
            current.width = frame.width
            current.height = frame.height
            prefs.widgets.setFrame(current, for: kind)
        }
        store.onChange = { [weak self] in
            self?.syncWidgets()
            self?.settings?.reload()
        }
    }

    private func clamped(_ rect: NSRect) -> NSRect {
        let screens = NSScreen.screens.map(\.visibleFrame)
        guard let screen = screens.first(where: { $0.intersects(rect) }) ?? screens.first else { return rect }
        var copy = rect
        copy.size.width = min(copy.width, screen.width)
        copy.size.height = min(copy.height, screen.height)
        if copy.maxX > screen.maxX { copy.origin.x = screen.maxX - copy.width }
        if copy.minX < screen.minX { copy.origin.x = screen.minX }
        if copy.maxY > screen.maxY { copy.origin.y = screen.maxY - copy.height }
        if copy.minY < screen.minY { copy.origin.y = screen.minY }
        return copy
    }

    @objc func openSettings() {
        if settings == nil {
            let controller = SettingsWindowController(store: store)
            controller.onPick = { [weak self] in self?.pickDatabase() }
            controller.onMove = { [weak self] in self?.moveDatabase() }
            controller.onExport = { [weak self] in self?.exportDatabase() }
            controller.onImport = { [weak self] in self?.importDatabase() }
            controller.onReset = { [weak self] in self?.resetFrames() }
            settings = controller
        }
        settings?.show()
    }

    @objc private func newEvent() { openEvent(nil) }
    @objc private func newReminder() { openReminder(nil) }

    private func showItem(_ title: String, _ kind: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(toggleShown(_:)), keyEquivalent: "")
        item.target = self
        item.identifier = NSUserInterfaceItemIdentifier(kind)
        return item
    }

    @objc private func toggleShown(_ sender: NSMenuItem) {
        guard let kind = sender.identifier?.rawValue else { return }
        store.updatePreferences { prefs in
            var frame = prefs.widgets.frame(for: kind)
            frame.visible.toggle()
            prefs.widgets.setFrame(frame, for: kind)
        }
        settings?.reload()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let kinds = ["schedule", "reminders", "combined"]
        for item in menu.items {
            let kind = item.identifier?.rawValue ?? ""
            if kinds.contains(kind) {
                item.state = store.database.preferences.widgets.frame(for: kind).visible ? .on : .off
            } else {
                item.state = .off
            }
        }
    }

    private func openEvent(_ id: UUID?, occurrence: Date? = nil) {
        if let editor = editors.compactMap({ $0 as? EventEditorWindow }).first(where: { $0.existingID == id }) {
            editor.show()
            return
        }
        guard acceptOpen(id == nil ? "event-new" : "event-\(id!.uuidString)") else { return }
        let editor = EventEditorWindow(store: store, existingID: id, occurrence: occurrence)
        editor.onClose = { [weak self, weak editor] in self?.editors.removeAll { $0 === editor } }
        editors.append(editor)
        editor.show()
    }

    private func openReminder(_ id: UUID?) {
        if let editor = editors.compactMap({ $0 as? ReminderEditorWindow }).first(where: { $0.existingID == id }) {
            editor.show()
            return
        }
        guard acceptOpen(id == nil ? "reminder-new" : "reminder-\(id!.uuidString)") else { return }
        let editor = ReminderEditorWindow(store: store, existingID: id)
        editor.onClose = { [weak self, weak editor] in self?.editors.removeAll { $0 === editor } }
        editors.append(editor)
        editor.show()
    }

    private func acceptOpen(_ key: String) -> Bool {
        let now = Date()
        if let previous = lastOpen[key], now.timeIntervalSince(previous) < 0.5 { return false }
        lastOpen[key] = now
        return true
    }

    private func pickDatabase() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.message = "选择 macOS 或 Windows 上保存的日程台 JSON 数据库"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let error = store.useDatabase(at: url, createIfMissing: false) { alert(error) }
    }

    private func moveDatabase() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "日程台数据.json"
        panel.message = "数据库会改用这个新位置，原文件仍会保留"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let error = store.useDatabase(at: url, createIfMissing: true) { alert(error) }
    }

    private func exportDatabase() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "日程台数据.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try store.database.encode().write(to: url, options: .atomic) } catch { alert(error.localizedDescription) }
    }

    private func importDatabase() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.message = "导入会替换当前的偏好、日程和提醒事项"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let alertBox = NSAlert()
        alertBox.messageText = "用所选文件替换当前数据库？"
        alertBox.informativeText = "偏好设置、日程和提醒事项都会被替换。"
        alertBox.addButton(withTitle: "替换")
        alertBox.addButton(withTitle: "取消")
        guard alertBox.runModal() == .alertFirstButtonReturn, let data = try? Data(contentsOf: url) else { return }
        if let error = store.replace(with: data) { alert(error) }
    }

    private func resetFrames() {
        store.updatePreferences { prefs in
            prefs.widgets.schedule.visible = false
            prefs.widgets.reminders.visible = false
            prefs.widgets.combined.visible = false
        }
        widgets.values.forEach { $0.close() }
        widgets.removeAll()
        syncWidgets()
    }

    private func alert(_ text: String) {
        let box = NSAlert()
        box.messageText = text
        box.runModal()
    }

    private func armTimer() {
        timer?.invalidate()
        checkNotices()
        let delay: TimeInterval
        if let next = Logic.nextWake(store.database, now: Date()) {
            delay = min(30, max(0.4, next.timeIntervalSinceNow))
        } else {
            delay = 30
        }
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.armTimer()
        }
    }

    private func checkNotices() {
        let due = Logic.dueItems(store.database, now: Date())
        guard !due.isEmpty else { return }
        store.onChange = nil
        store.markFired(due.map(\.key))
        store.onChange = { [weak self] in
            self?.syncWidgets()
            self?.armTimer()
        }
        pendingNotices.append(contentsOf: due)
        showNotices(pendingNotices)
        if store.database.preferences.soundEnabled {
            (NSSound(named: "Glass") ?? NSSound(named: "Ping"))?.play()
        }
    }

    private func showNotices(_ items: [Notice]) {
        if notice == nil {
            let panel = NoticeWindow(store: store)
            panel.onClose = { [weak self] in
                self?.pendingNotices.removeAll()
                self?.notice?.window.close()
            }
            panel.onSnooze = { [weak self] in
                guard let self else { return }
                let keys = self.pendingNotices.map(\.key)
                self.pendingNotices.removeAll()
                self.notice?.window.close()
                self.store.snooze(keys, minutes: 5)
                self.armTimer()
            }
            notice = panel
        }
        notice?.show(items)
    }
}
