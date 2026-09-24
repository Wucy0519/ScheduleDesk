import AppKit
import CoreText

enum Chrome {
    static let background = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
    static let green = NSColor(srgbRed: 0.61, green: 0.91, blue: 0.71, alpha: 1)
    static let purple = NSColor(srgbRed: 0.84, green: 0.71, blue: 0.97, alpha: 1)
    static let conflict = NSColor(srgbRed: 1, green: 0.27, blue: 0.23, alpha: 1)
    static let orange = NSColor(srgbRed: 1, green: 0.42, blue: 0.24, alpha: 1)
    static let card = NSColor(srgbRed: 0.17, green: 0.17, blue: 0.18, alpha: 1)
}

protocol Reloading: AnyObject { func reload() }

final class WheelControl: NSView {
    struct Column {
        var title: String
        var values: [Int]
        var loop: Bool
        var value: Int
        var label: (Int) -> String
    }

    var columns: [Column] = [] { didSet { needsDisplay = true } }
    var onChange: (() -> Void)?
    var sensitivity: () -> Double = { 1 }
    private var selectedColumn = 0
    private var armed = false
    private var scrollBucket: CGFloat = 0
    private let rowHeight: CGFloat = 36
    private var keyMonitor: Any?

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: hasTitles ? 210 : 180) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setContentCompressionResistancePriority(.required, for: .vertical)
        setContentHuggingPriority(.required, for: .vertical)
        clipsToBounds = true
        updateTrackingAreas()
    }

    required init?(coder: NSCoder) { nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let wheelMid = bounds.midY - (hasTitles ? 12 : 0)
        let band = NSRect(x: 8, y: wheelMid - rowHeight / 2, width: bounds.width - 16, height: rowHeight)
        let bandPath = NSBezierPath(roundedRect: band, xRadius: 8, yRadius: 8)
        NSColor.white.withAlphaComponent(window?.firstResponder === self ? 0.14 : 0.08).setFill()
        bandPath.fill()
        if window?.firstResponder === self {
            Chrome.orange.withAlphaComponent(0.8).setStroke()
            bandPath.lineWidth = 1
            bandPath.stroke()
        }
        guard !columns.isEmpty else { return }
        let width = bounds.width / CGFloat(columns.count)
        let focused = window?.firstResponder === self
        if focused {
            let columnBand = NSRect(x: CGFloat(selectedColumn) * width + 4, y: wheelMid - rowHeight / 2, width: width - 8, height: rowHeight)
            NSColor.white.withAlphaComponent(0.16).setFill()
            NSBezierPath(roundedRect: columnBand, xRadius: 8, yRadius: 8).fill()
        }
        for (index, column) in columns.enumerated() {
            if !column.title.isEmpty {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 12, weight: focused && index == selectedColumn ? .semibold : .regular),
                    .foregroundColor: focused && index == selectedColumn ? Chrome.orange : NSColor.secondaryLabelColor
                ]
                let size = (column.title as NSString).size(withAttributes: attrs)
                (column.title as NSString).draw(at: NSPoint(x: CGFloat(index) * width + (width - size.width) / 2, y: bounds.height - size.height - 4), withAttributes: attrs)
            }
            for offset in -2...2 {
                guard let text = label(column, offset: offset) else { continue }
                let alpha: CGFloat = offset == 0 ? 1 : (abs(offset) == 1 ? 0.55 : 0.28)
                let activeColumn = !focused || index == selectedColumn
                let color = offset == 0 && activeColumn ? Chrome.orange : NSColor.white.withAlphaComponent(offset == 0 ? 0.85 : alpha)
                let font = NSFont.monospacedDigitSystemFont(ofSize: offset == 0 ? 22 : 16, weight: offset == 0 ? .semibold : .regular)
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                let size = (text as NSString).size(withAttributes: attrs)
                let rowY = wheelMid - rowHeight / 2 - CGFloat(offset) * rowHeight
                (text as NSString).draw(at: NSPoint(x: CGFloat(index) * width + (width - size.width) / 2, y: rowY + (rowHeight - size.height) / 2), withAttributes: attrs)
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let column = columnAt(event) else { return }
        armed = true
        selectedColumn = column
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        let wheelMid = bounds.midY - (hasTitles ? 12 : 0)
        let offset = Int((wheelMid - point.y) / rowHeight)
        if offset != 0 { step(offset) } else { needsDisplay = true }
    }

    override func scrollWheel(with event: NSEvent) {
        guard armed, window?.firstResponder === self, columnAt(event) == selectedColumn else {
            super.scrollWheel(with: event)
            return
        }
        guard abs(event.scrollingDeltaY) > 0.1 else { return }
        let steps = consumeScroll(event)
        guard steps != 0 else { return }
        step(-steps)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
    }

    override func mouseExited(with event: NSEvent) {
        disarm()
    }

    override func mouseMoved(with event: NSEvent) {
        guard armed, columnAt(event) != selectedColumn else { return }
        disarm()
    }

    override func becomeFirstResponder() -> Bool {
        installKeyMonitor()
        needsDisplay = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        armed = false
        removeKeyMonitor()
        needsDisplay = true
        return true
    }

    override func keyDown(with event: NSEvent) {
        if handleArrow(event) { return }
        super.keyDown(with: event)
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window, self.window?.firstResponder === self else { return event }
            return self.handleArrow(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func handleArrow(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 126: step(-1)
        case 125: step(1)
        case 123: moveColumn(-1)
        case 124: moveColumn(1)
        default: return false
        }
        return true
    }

    private func moveColumn(_ delta: Int) {
        guard !columns.isEmpty else { return }
        selectedColumn = min(max(selectedColumn + delta, 0), columns.count - 1)
        needsDisplay = true
    }

    private func columnAt(_ event: NSEvent) -> Int? {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point), !columns.isEmpty else { return nil }
        let width = bounds.width / CGFloat(columns.count)
        return min(columns.count - 1, max(0, Int(point.x / width)))
    }

    private func consumeScroll(_ event: NSEvent) -> Int {
        let level = min(5, max(1, sensitivity()))
        if event.hasPreciseScrollingDeltas {
            let threshold = CGFloat(140 - (level - 1) * 26)
            scrollBucket += event.scrollingDeltaY
            let steps = Int(scrollBucket / threshold)
            if steps != 0 { scrollBucket -= CGFloat(steps) * threshold }
            return steps
        }
        let notch: CGFloat = event.scrollingDeltaY > 0 ? 1 : -1
        let need = CGFloat(6 - level)
        scrollBucket += notch
        let steps = Int(scrollBucket / need)
        if steps != 0 { scrollBucket -= CGFloat(steps) * need }
        return steps
    }

    private func disarm() {
        scrollBucket = 0
        guard armed || window?.firstResponder === self else { return }
        armed = false
        if window?.firstResponder === self {
            window?.makeFirstResponder(nil)
        }
        needsDisplay = true
    }

    private var hasTitles: Bool { columns.contains { !$0.title.isEmpty } }

    private func label(_ column: Column, offset: Int) -> String? {
        guard let index = column.values.firstIndex(of: column.value) ?? column.values.indices.first else { return nil }
        let target = index + offset
        if column.loop, !column.values.isEmpty {
            let count = column.values.count
            return column.label(column.values[((target % count) + count) % count])
        }
        guard column.values.indices.contains(target) else { return nil }
        return column.label(column.values[target])
    }

    private func step(_ delta: Int) {
        guard columns.indices.contains(selectedColumn) else { return }
        var column = columns[selectedColumn]
        guard let index = column.values.firstIndex(of: column.value) else { return }
        let target = index + delta
        if column.loop, !column.values.isEmpty {
            let count = column.values.count
            column.value = column.values[((target % count) + count) % count]
        } else if column.values.indices.contains(target) {
            column.value = column.values[target]
        } else {
            return
        }
        columns[selectedColumn] = column
        onChange?()
        needsDisplay = true
    }
}

final class ScheduleWidgetView: NSView, Reloading {
    let store: Store
    var onCreate: () -> Void
    var onOpen: (UUID, Date) -> Void
    private let pinKind: String?
    private let pinColor = Chrome.green
    private let pinButton = NSButton()
    private let hideButton = NSButton()
    private let stack = NSStackView()
    private let scroll = NSScrollView()
    private let document = FlippedView()
    private var keys: [String] = []
    private var selected: String?
    private var rows: [String: NSView] = [:]
    private var rowWidths: [NSLayoutConstraint] = []
    private var holdToday = true
    private var pinning = false
    private var showHistory = false
    private var nowAnchor: NSView?

    init(store: Store, pinKind: String?, onCreate: @escaping () -> Void, onOpen: @escaping (UUID, Date) -> Void) {
        self.store = store
        self.pinKind = pinKind
        self.onCreate = onCreate
        self.onOpen = onOpen
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Chrome.background.cgColor
        let header = NSTextField(labelWithString: "日程")
        header.font = .systemFont(ofSize: 17, weight: .semibold)
        header.textColor = .white
        let plus = symbolButton("plus.circle", "创建新的日程", Chrome.green, #selector(create))
        plus.target = self
        let controls: [NSView]
        if pinKind != nil {
            configurePin(pinButton, color: Chrome.green, action: #selector(togglePin))
            pinButton.target = self
            configureChip(hideButton, title: "隐藏", color: Chrome.green, action: #selector(hideWindow))
            hideButton.target = self
            controls = [header, NSView(), hideButton, pinButton, plus]
        } else {
            controls = [header, NSView(), plus]
        }
        let bar = NSStackView(views: controls)
        bar.orientation = .horizontal
        bar.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 8, right: 16)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 12, bottom: 16, right: 12)
        stack.clipsToBounds = true
        document.clipsToBounds = true
        document.addSubview(stack)
        let clip = FlippedClipView()
        clip.drawsBackground = false
        scroll.contentView = clip
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = document
        let root = NSStackView(views: [bar, scroll])
        root.orientation = .vertical
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: topAnchor),
            root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor),
            root.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
    }

    required init?(coder: NSCoder) { nil }

    func reload() {
        let keep = selected
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        rows.removeAll()
        keys.removeAll()
        rowWidths.removeAll()
        let font = CGFloat(store.database.preferences.fontSize)
        let now = Date()
        let today = Logic.format(now, time: false)
        nowAnchor = nil
        var upcomingAnchor: NSView?
        for group in Logic.agenda(events: store.database.events, now: now, pastDays: showHistory ? 90 : 0) {
            let passed = group.items.filter { !$0.event.allDay && $0.end <= now }
            let current = group.items.filter { $0.event.allDay || $0.end > now }
            if group.id < today {
                appendDay(group.date, items: group.items, font: font, today: today)
            } else if group.id == today {
                let todayItems = (passed + current).sorted { $0.start < $1.start }
                if todayItems.isEmpty {
                    upcomingAnchor = appendDay(group.date, items: [], font: font, today: today, emptyIfNone: true)
                } else {
                    upcomingAnchor = appendDay(group.date, items: todayItems, font: font, today: today)
                }
            } else {
                appendDay(group.date, items: current, font: font, today: today, emptyIfNone: current.isEmpty && group.date < Logic.addDays(now, 3))
            }
        }
        nowAnchor = upcomingAnchor
        selected = keys.contains(keep ?? "") ? keep : nil
        refreshPin()
        refreshSelection()
        layoutDocument()
        placeAtNowIfNeeded()
    }

    override func layout() {
        super.layout()
        layoutDocument()
        placeAtNowIfNeeded()
    }

    @discardableResult
    private func appendDay(_ date: Date, items: [Occurrence], font: CGFloat, today: String, emptyIfNone: Bool = false) -> NSView? {
        let headingText = Logic.dayHeading(date, today: Logic.startOfDay(Date()))
        let heading = NSTextField(labelWithString: headingText)
        heading.alignment = .left
        let headingFont = NSFont.systemFont(ofSize: font + 1, weight: .semibold)
        if Logic.format(date, time: false) == today {
            let styled = NSMutableAttributedString(string: headingText, attributes: [
                .font: headingFont,
                .foregroundColor: NSColor.white
            ])
            let weekday = Logic.weekdayShort[Logic.weekdayIndex(date)]
            if let range = headingText.range(of: weekday) {
                styled.addAttributes([
                    .font: NSFont.systemFont(ofSize: font + 1, weight: .bold),
                    .foregroundColor: NSColor(srgbRed: 1, green: 0.38, blue: 0.16, alpha: 1)
                ], range: NSRange(range, in: headingText))
            }
            heading.attributedStringValue = styled
        } else {
            heading.font = headingFont
            heading.textColor = .secondaryLabelColor
        }
        if items.isEmpty {
            guard emptyIfNone else { return nil }
            heading.lineBreakMode = .byTruncatingTail
            heading.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
            let empty = NSTextField(labelWithString: "当前无日程")
            empty.font = .systemFont(ofSize: max(11, font - 1))
            empty.textColor = .secondaryLabelColor
            empty.alignment = .right
            empty.lineBreakMode = .byTruncatingTail
            empty.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            empty.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            let spacer = NSView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let lineHead = NSStackView(views: [heading, spacer, empty])
            lineHead.orientation = .horizontal
            lineHead.alignment = .centerY
            lineHead.clipsToBounds = true
            stack.addArrangedSubview(lineHead)
            trackWidth(lineHead)
            let line = NSBox()
            line.boxType = .custom
            line.fillColor = NSColor.white.withAlphaComponent(0.28)
            line.borderWidth = 0
            line.translatesAutoresizingMaskIntoConstraints = false
            line.heightAnchor.constraint(equalToConstant: 1).isActive = true
            stack.addArrangedSubview(line)
            trackWidth(line)
            return lineHead
        }
        pinLeft(heading)
        let header = stack.arrangedSubviews.last
        for item in items {
            keys.append(item.id)
            let row = eventRow(item, font: font)
            rows[item.id] = row
            stack.addArrangedSubview(row)
        }
        return items.isEmpty ? header : rows[items[0].id]
    }

    private func placeAtNowIfNeeded() {
        guard holdToday, !showHistory, scroll.contentView.bounds.height > 20 else { return }
        pinning = true
        let top: CGFloat = scroll.contentView.isFlipped ? 0 : max(0, document.frame.height - scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: top))
        scroll.reflectScrolledClipView(scroll.contentView)
        pinning = false
    }

    override func scrollWheel(with event: NSEvent) {
        let atTop = scroll.contentView.bounds.origin.y <= 2
        if !showHistory && atTop && event.scrollingDeltaY > 0 {
            showHistory = true
            holdToday = false
            reload()
            if let nowAnchor {
                let y = nowAnchor.convert(NSPoint.zero, to: document).y
                scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, y - 72)))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
            return
        }
        holdToday = false
        super.scrollWheel(with: event)
    }

    private func layoutDocument() {
        let width = scroll.contentView.bounds.width
        guard width > 20 else { return }
        let inner = max(1, width - 24)
        for constraint in rowWidths { constraint.constant = inner }
        stack.layoutSubtreeIfNeeded()
        let height = max(stack.fittingSize.height, 1)
        stack.frame = NSRect(x: 0, y: 0, width: width, height: height)
        document.frame = NSRect(x: 0, y: 0, width: width, height: max(height, scroll.contentView.bounds.height))
    }

    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 125: move(1)
        case 126: move(-1)
        case 36, 76: openSelected()
        default: super.keyDown(with: event)
        }
    }

    @objc private func create() { onCreate() }

    @objc private func togglePin() {
        guard let pinKind else { return }
        store.updatePreferences { prefs in
            if pinKind == "combined" { prefs.combinedOnTop.toggle() }
            else { prefs.scheduleOnTop.toggle() }
        }
        refreshPin()
    }

    private func refreshPin() {
        guard let pinKind else { return }
        let on = pinKind == "combined" ? store.database.preferences.combinedOnTop : store.database.preferences.scheduleOnTop
        stylePin(pinButton, color: pinColor, on: on)
    }

    @objc private func hideWindow() {
        guard let pinKind else { return }
        store.updatePreferences { prefs in
            var frame = prefs.widgets.frame(for: pinKind)
            frame.visible = false
            prefs.widgets.setFrame(frame, for: pinKind)
        }
    }

    private func eventRow(_ item: Occurrence, font: CGFloat) -> NSView {
        let colors = store.database.preferences
        let time = Logic.timeLabel(item)
        let timeFont = NSFont.monospacedSystemFont(ofSize: max(12, font - 1), weight: .bold)
        let timeInset = ("  " as NSString).size(withAttributes: [.font: timeFont]).width
        let startLabel = NSTextField(labelWithString: time.start)
        startLabel.font = timeFont
        startLabel.textColor = NSColor(hex: colors.startColor) ?? Chrome.green
        startLabel.alignment = .left
        startLabel.lineBreakMode = .byClipping
        let timeColumn = NSStackView(views: [startLabel])
        timeColumn.orientation = .vertical
        timeColumn.alignment = .leading
        timeColumn.spacing = 2
        timeColumn.translatesAutoresizingMaskIntoConstraints = false
        if !time.end.isEmpty {
            let endLabel = NSTextField(labelWithString: time.end)
            endLabel.font = .monospacedSystemFont(ofSize: max(11, font - 2), weight: .regular)
            endLabel.textColor = NSColor(hex: colors.endColor) ?? NSColor(white: 0.62, alpha: 1)
            endLabel.alignment = .left
            endLabel.lineBreakMode = .byClipping
            timeColumn.addArrangedSubview(endLabel)
        }
        let title = NSTextField(labelWithString: item.event.title)
        title.font = .systemFont(ofSize: font, weight: .semibold)
        title.textColor = NSColor(srgbRed: 0.82, green: 0.9, blue: 0.96, alpha: 1)
        title.lineBreakMode = .byTruncatingTail
        title.maximumNumberOfLines = 1
        let textColumn = NSStackView(views: [title])
        textColumn.orientation = .vertical
        textColumn.alignment = .leading
        textColumn.spacing = 2
        if !item.event.notes.isEmpty {
            let notes = NSTextField(labelWithString: item.event.notes)
            notes.font = .systemFont(ofSize: max(11, font - 3))
            notes.textColor = NSColor(white: 0.78, alpha: 0.75)
            notes.lineBreakMode = .byTruncatingTail
            notes.maximumNumberOfLines = 1
            textColumn.addArrangedSubview(notes)
        }
        if item.conflict {
            let badge = NSTextField(labelWithString: "有冲突")
            badge.font = .systemFont(ofSize: max(11, font - 3), weight: .semibold)
            badge.textColor = Chrome.orange
            textColumn.addArrangedSubview(badge)
        }
        let accent = NSView()
        accent.wantsLayer = true
        let cardColor = NSColor(hex: colors.cardColor) ?? NSColor(srgbRed: 0.35, green: 0.41, blue: 0.45, alpha: 1)
        accent.layer?.backgroundColor = cardColor.blended(withFraction: 0.45, of: .white)?.cgColor
        accent.translatesAutoresizingMaskIntoConstraints = false
        accent.widthAnchor.constraint(equalToConstant: 3).isActive = true
        let card = NSStackView(views: [accent, textColumn])
        card.orientation = .horizontal
        card.alignment = .centerY
        card.spacing = 8
        card.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 10)
        card.wantsLayer = true
        card.layer?.backgroundColor = cardColor.cgColor
        card.layer?.cornerRadius = 8
        card.setContentHuggingPriority(.defaultLow, for: .horizontal)
        card.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        card.translatesAutoresizingMaskIntoConstraints = false
        card.heightAnchor.constraint(equalToConstant: 58).isActive = true
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        timeColumn.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(timeColumn)
        row.addSubview(card)
        NSLayoutConstraint.activate([
            timeColumn.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: timeInset),
            timeColumn.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            timeColumn.widthAnchor.constraint(equalToConstant: 56),
            card.leadingAnchor.constraint(equalTo: timeColumn.trailingAnchor, constant: 8),
            card.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            card.topAnchor.constraint(equalTo: row.topAnchor, constant: 4),
            card.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -4)
        ])
        trackWidth(row)
        if !item.event.notes.isEmpty { row.toolTip = item.event.notes }
        row.alphaValue = item.end <= Date() ? 0.45 : 1
        let click = ClickCatcher { [weak self] in self?.activate(item) }
        click.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(click)
        NSLayoutConstraint.activate([
            click.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            click.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            click.topAnchor.constraint(equalTo: row.topAnchor),
            click.bottomAnchor.constraint(equalTo: row.bottomAnchor)
        ])
        return row
    }

    private func pinLeft(_ label: NSTextField) {
        label.translatesAutoresizingMaskIntoConstraints = false
        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            label.topAnchor.constraint(equalTo: wrap.topAnchor),
            label.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
        ])
        trackWidth(wrap)
        stack.addArrangedSubview(wrap)
    }

    private func trackWidth(_ view: NSView) {
        let constraint = view.widthAnchor.constraint(equalToConstant: max(1, scroll.contentView.bounds.width - 24))
        constraint.isActive = true
        rowWidths.append(constraint)
    }

    private func activate(_ item: Occurrence) {
        window?.makeFirstResponder(self)
        if selected == item.id { onOpen(item.event.id, item.start) } else { selected = item.id; refreshSelection() }
    }

    private func move(_ delta: Int) {
        guard !keys.isEmpty else { return }
        let index = keys.firstIndex(of: selected ?? "") ?? (delta > 0 ? -1 : 0)
        selected = keys[min(max(index + delta, 0), keys.count - 1)]
        refreshSelection()
        if let selected, let row = rows[selected] { row.scrollToVisible(row.bounds) }
    }

    private func openSelected() {
        guard let selected, let item = Logic.agenda(events: store.database.events, now: Date(), pastDays: 90).flatMap(\.items).first(where: { $0.id == selected }) else { return }
        onOpen(item.event.id, item.start)
    }

    private func refreshSelection() {
        for (key, row) in rows {
            row.wantsLayer = true
            row.layer?.backgroundColor = key == selected ? NSColor.white.withAlphaComponent(0.08).cgColor : NSColor.clear.cgColor
            row.layer?.cornerRadius = 10
        }
    }
}

final class ReminderWidgetView: NSView, Reloading {
    let store: Store
    var onCreate: () -> Void
    var onOpen: (UUID) -> Void
    private let pinKind: String?
    private let pinButton = NSButton()
    private let hideButton = NSButton()
    private let stack = NSStackView()
    private let scroll = NSScrollView()
    private let document = FlippedView()
    private var ids: [UUID] = []
    private var selected: UUID?
    private var rows: [UUID: NSView] = [:]

    init(store: Store, pinKind: String?, onCreate: @escaping () -> Void, onOpen: @escaping (UUID) -> Void) {
        self.store = store
        self.pinKind = pinKind
        self.onCreate = onCreate
        self.onOpen = onOpen
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Chrome.background.cgColor
        let header = NSTextField(labelWithString: "提醒事项")
        header.font = .systemFont(ofSize: 17, weight: .semibold)
        header.textColor = .white
        let plus = symbolButton("plus.circle", "创建新的提醒事项", Chrome.purple, #selector(create))
        plus.target = self
        let controls: [NSView]
        if pinKind != nil {
            configurePin(pinButton, color: Chrome.purple, action: #selector(togglePin))
            pinButton.target = self
            configureChip(hideButton, title: "隐藏", color: Chrome.purple, action: #selector(hideWindow))
            hideButton.target = self
            controls = [header, NSView(), hideButton, pinButton, plus]
        } else {
            controls = [header, NSView(), plus]
        }
        let bar = NSStackView(views: controls)
        bar.orientation = .horizontal
        bar.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 8, right: 16)
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 16, right: 8)
        document.addSubview(stack)
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = document
        let root = NSStackView(views: [bar, scroll])
        root.orientation = .vertical
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: topAnchor),
            root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor),
            root.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }

    func reload() {
        let keep = selected
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        rows.removeAll()
        ids.removeAll()
        let font = CGFloat(store.database.preferences.fontSize)
        let showCompleted = store.database.preferences.showCompletedReminders
        let split = Logic.splitReminders(store.database.reminders, now: Date())
        if split.open.isEmpty && (!showCompleted || split.done.isEmpty) {
            stack.addArrangedSubview(secondary(split.done.isEmpty ? "没有提醒事项" : "没有未完成的提醒事项", size: font - 1))
        }
        split.open.forEach { add($0, font: font) }
        if showCompleted && !split.done.isEmpty {
            if !split.open.isEmpty {
                let line = NSBox()
                line.boxType = .custom
                line.fillColor = NSColor.white.withAlphaComponent(0.28)
                line.borderWidth = 0
                line.translatesAutoresizingMaskIntoConstraints = false
                line.heightAnchor.constraint(equalToConstant: 1).isActive = true
                stack.addArrangedSubview(line)
            }
            split.done.forEach { add($0, font: font) }
        }
        selected = ids.contains(keep ?? UUID()) ? keep : nil
        refreshPin()
        refreshSelection()
        layoutDocument()
    }

    override func layout() {
        super.layout()
        layoutDocument()
    }

    private func layoutDocument() {
        let width = scroll.contentView.bounds.width
        guard width > 20 else { return }
        stack.layoutSubtreeIfNeeded()
        let height = max(stack.fittingSize.height, 1)
        stack.frame = NSRect(x: 0, y: 0, width: width, height: height)
        document.frame = NSRect(x: 0, y: 0, width: width, height: max(height, scroll.contentView.bounds.height))
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 125: move(1)
        case 126: move(-1)
        case 36, 76: if let selected { onOpen(selected) }
        case 49: if let selected { store.toggleReminder(selected) }
        default: super.keyDown(with: event)
        }
    }

    @objc private func create() { onCreate() }

    @objc private func togglePin() {
        store.updatePreferences { $0.remindersOnTop.toggle() }
        refreshPin()
    }

    private func refreshPin() {
        guard pinKind != nil else { return }
        stylePin(pinButton, color: Chrome.purple, on: store.database.preferences.remindersOnTop)
    }

    @objc private func hideWindow() {
        store.updatePreferences { prefs in
            var frame = prefs.widgets.reminders
            frame.visible = false
            prefs.widgets.reminders = frame
        }
    }

    private func add(_ item: ReminderItem, font: CGFloat) {
        ids.append(item.id)
        let circle = NSButton()
        circle.bezelStyle = .shadowlessSquare
        circle.isBordered = false
        circle.image = NSImage(systemSymbolName: item.completed ? "checkmark.circle.fill" : "circle", accessibilityDescription: item.completed ? "标为未完成" : "标为已完成")
        circle.contentTintColor = item.completed ? Chrome.purple : NSColor.white.withAlphaComponent(0.45)
        circle.target = self
        circle.action = #selector(toggle(_:))
        circle.identifier = NSUserInterfaceItemIdentifier(item.id.uuidString)
        circle.translatesAutoresizingMaskIntoConstraints = false
        circle.imageScaling = .scaleProportionallyDown
        circle.imagePosition = .imageOnly
        let title = NSTextField(labelWithString: item.title)
        title.font = .systemFont(ofSize: font, weight: .medium)
        title.textColor = item.completed ? .secondaryLabelColor : .white
        title.alignment = .left
        if item.completed { title.attributedStringValue = NSAttributedString(string: item.title, attributes: [.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: NSColor.secondaryLabelColor, .font: title.font!]) }
        let column = NSStackView(views: [title])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 2
        if !item.notes.isEmpty {
            let notes = NSTextField(wrappingLabelWithString: item.notes)
            notes.font = .systemFont(ofSize: max(11, font - 3))
            notes.textColor = NSColor(white: 0.62, alpha: 1)
            notes.maximumNumberOfLines = 2
            notes.lineBreakMode = .byTruncatingTail
            column.addArrangedSubview(notes)
        }
        if let due = item.due.flatMap(Logic.parse) {
            let dueLabel = NSTextField(labelWithString: Logic.dueLabel(due, now: Date()))
            dueLabel.font = .systemFont(ofSize: max(11, font - 2))
            dueLabel.textColor = !item.completed && due < Date() ? Chrome.conflict : .secondaryLabelColor
            column.addArrangedSubview(dueLabel)
        }
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        column.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(circle)
        row.addSubview(column)
        let mark = font + 6
        NSLayoutConstraint.activate([
            circle.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 8),
            circle.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            circle.widthAnchor.constraint(equalToConstant: mark),
            circle.heightAnchor.constraint(equalToConstant: mark),
            column.leadingAnchor.constraint(equalTo: circle.trailingAnchor, constant: 8),
            column.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -8),
            column.topAnchor.constraint(equalTo: row.topAnchor, constant: 6),
            column.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -6)
        ])
        if !item.notes.isEmpty { row.toolTip = item.notes }
        let click = ClickCatcher { [weak self] in self?.activate(item.id) }
        click.translatesAutoresizingMaskIntoConstraints = false
        column.addSubview(click)
        NSLayoutConstraint.activate([
            click.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            click.trailingAnchor.constraint(equalTo: column.trailingAnchor),
            click.topAnchor.constraint(equalTo: column.topAnchor),
            click.bottomAnchor.constraint(equalTo: column.bottomAnchor)
        ])
        rows[item.id] = row
        stack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -8).isActive = true
    }

    private func activate(_ id: UUID) {
        window?.makeFirstResponder(self)
        if selected == id { onOpen(id) } else { selected = id; refreshSelection() }
    }

    @objc private func toggle(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let id = UUID(uuidString: raw) else { return }
        store.toggleReminder(id)
    }

    private func move(_ delta: Int) {
        guard !ids.isEmpty else { return }
        let index = ids.firstIndex(of: selected ?? UUID()) ?? (delta > 0 ? -1 : 0)
        selected = ids[min(max(index + delta, 0), ids.count - 1)]
        refreshSelection()
    }

    private func refreshSelection() {
        for (id, row) in rows {
            row.wantsLayer = true
            row.layer?.backgroundColor = id == selected ? NSColor.white.withAlphaComponent(0.08).cgColor : NSColor.clear.cgColor
            row.layer?.cornerRadius = 10
        }
    }
}

final class CombinedWidgetView: NSView, Reloading {
    let reminders: ReminderWidgetView
    let schedule: ScheduleWidgetView
    init(store: Store, onCreateEvent: @escaping () -> Void, onCreateReminder: @escaping () -> Void, onOpenEvent: @escaping (UUID, Date) -> Void, onOpenReminder: @escaping (UUID) -> Void) {
        reminders = ReminderWidgetView(store: store, pinKind: nil, onCreate: onCreateReminder, onOpen: onOpenReminder)
        schedule = ScheduleWidgetView(store: store, pinKind: "combined", onCreate: onCreateEvent, onOpen: onOpenEvent)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Chrome.background.cgColor
        let divider = NSBox()
        divider.boxType = .custom
        divider.fillColor = NSColor.white.withAlphaComponent(0.08)
        divider.borderWidth = 0
        divider.translatesAutoresizingMaskIntoConstraints = false
        reminders.translatesAutoresizingMaskIntoConstraints = false
        schedule.translatesAutoresizingMaskIntoConstraints = false
        addSubview(reminders)
        addSubview(divider)
        addSubview(schedule)
        NSLayoutConstraint.activate([
            reminders.leadingAnchor.constraint(equalTo: leadingAnchor),
            reminders.topAnchor.constraint(equalTo: topAnchor),
            reminders.bottomAnchor.constraint(equalTo: bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: reminders.trailingAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            divider.topAnchor.constraint(equalTo: topAnchor),
            divider.bottomAnchor.constraint(equalTo: bottomAnchor),
            schedule.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            schedule.trailingAnchor.constraint(equalTo: trailingAnchor),
            schedule.topAnchor.constraint(equalTo: topAnchor),
            schedule.bottomAnchor.constraint(equalTo: bottomAnchor),
            schedule.widthAnchor.constraint(equalTo: reminders.widthAnchor)
        ])
    }
    required init?(coder: NSCoder) { nil }
    func reload() { reminders.reload(); schedule.reload() }
}

final class EventEditorWindow: NSObject, NSWindowDelegate {
    let window: NSWindow
    var onClose: (() -> Void)?
    private let store: Store
    let existingID: UUID?
    private let occurrence: Date?
    private let container = NSView()
    private var page = "form"
    private var titleField = NSTextField()
    private var notesField = NSTextField()
    private var allDaySwitch = NSSwitch()
    private var repeatButton = NSButton()
    private var conflictLabel = NSTextField(labelWithString: "")
    private var hint = NSTextField(labelWithString: "")
    private let startWheel = WheelControl()
    private let endWheel = WheelControl()
    private var endLinked = true
    private var rule = RepeatRule.none()
    private var custom = RepeatRule.none()
    private var createdAt = ""
    private var repeatHighlight = 0
    private var weekdayHighlight = 0
    private let customInterval = WheelControl()
    private let untilWheel = WheelControl()

    init(store: Store, existingID: UUID?, occurrence: Date? = nil) {
        self.store = store
        self.existingID = existingID
        self.occurrence = occurrence
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 780), styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init()
        window.title = existingID == nil ? "新建日程" : "编辑日程"
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Chrome.background
        window.level = .modalPanel
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = container
        window.minSize = NSSize(width: 460, height: 640)
        window.contentMinSize = NSSize(width: 460, height: 640)
        load()
        showForm()
        window.setContentSize(NSSize(width: 480, height: 760))
        window.center()
        let readSensitivity = { [weak self] in self?.store.database.preferences.scrollSensitivity ?? 1 }
        startWheel.sensitivity = readSensitivity
        endWheel.sensitivity = readSensitivity
        customInterval.sensitivity = readSensitivity
        untilWheel.sensitivity = readSensitivity
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            return self.handleKey(event) ? nil : event
        }
    }

    func show() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    func windowWillClose(_ notification: Notification) { onClose?() }

    private func load() {
        if let existingID, let event = store.database.events.first(where: { $0.id == existingID }) {
            titleField.stringValue = event.title
            notesField.stringValue = event.notes
            allDaySwitch.state = event.allDay ? .on : .off
            rule = event.repeatRule
            createdAt = event.createdAt
            endLinked = false
            setWheel(startWheel, raw: event.start, time: !event.allDay)
            setWheel(endWheel, raw: event.end, time: !event.allDay)
        } else {
            let start = Logic.nextHour()
            let end = Logic.defaultEnd(start: start, allDay: false)
            createdAt = Logic.nowStamp()
            endLinked = true
            setWheel(startWheel, raw: Logic.format(start, time: true), time: true)
            setWheel(endWheel, raw: Logic.format(end, time: true), time: true)
        }
    }

    private func showForm() {
        page = "form"
        container.subviews.forEach { $0.removeFromSuperview() }
        let heading = NSTextField(labelWithString: existingID == nil ? "新建日程" : "编辑日程")
        heading.font = .systemFont(ofSize: 15, weight: .semibold)
        heading.alignment = .center
        titleField = styledField(titleField.stringValue, placeholder: "日程名称", size: 22, bold: true)
        notesField = styledField(notesField.stringValue, placeholder: "备注", size: 15, bold: false)
        allDaySwitch.target = self
        allDaySwitch.action = #selector(allDayChanged)
        let allDayRow = labeledRow("全天", allDaySwitch)
        repeatButton = NSButton(title: "重复    \(Logic.repeatSummary(rule, start: startDate()))", target: self, action: #selector(openRepeats))
        repeatButton.bezelStyle = .rounded
        conflictLabel.stringValue = ""
        conflictLabel.textColor = Chrome.orange
        let showTime = allDaySwitch.state == .off
        hint.stringValue = endLinked && showTime ? "未指定结束时间时，默认为开始后 1 小时" : ""
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 12)
        hint.isHidden = hint.stringValue.isEmpty
        configureDateWheel(startWheel, time: showTime)
        configureDateWheel(endWheel, time: showTime)
        startWheel.onChange = { [weak self] in self?.startChanged() }
        endWheel.onChange = { [weak self] in self?.endLinked = false; self?.hint.isHidden = true; self?.refreshConflict() }
        let stack = NSStackView(views: [heading, titleField, notesField, allDayRow, repeatButton, conflictLabel, group("开始"), startWheel, group("结束"), hint, endWheel])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 18, bottom: 84, right: 18)
        mount(stack)
        pinGlassActions(on: container, cancel: #selector(close), save: #selector(saveEvent), tint: Chrome.green, target: self, delete: existingID == nil ? nil : #selector(deleteEvent))
        refreshConflict()
    }

    @objc private func openRepeats() {
        page = "repeats"
        container.subviews.forEach { $0.removeFromSuperview() }
        let header = editorHeader("重复", save: "完成", action: #selector(showFormAction))
        let options = ["不重复", "每天", "每周", "每月", "每年", "自定义"]
        let types = ["none", "daily", "weekly", "monthly", "yearly", "custom"]
        let list = NSStackView()
        list.orientation = .vertical
        list.spacing = 0
        for (index, name) in options.enumerated() {
            let button = NSButton(title: name, target: self, action: #selector(chooseRepeat(_:)))
            button.tag = index
            button.alignment = .left
            button.bezelStyle = .shadowlessSquare
            button.isBordered = false
            button.identifier = NSUserInterfaceItemIdentifier(types[index])
            if index == repeatHighlight { button.contentTintColor = Chrome.orange }
            if types[index] == rule.type { button.title = "\(name)  ✓" }
            list.addArrangedSubview(button)
            button.widthAnchor.constraint(equalToConstant: 400).isActive = true
            button.heightAnchor.constraint(equalToConstant: 36).isActive = true
        }
        let stack = NSStackView(views: [header, list, secondary("选中一项后可用键盘上下键，回车确认", size: 12)])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 18, bottom: 18, right: 18)
        mount(stack)
        window.makeFirstResponder(container)
    }

    @objc private func chooseRepeat(_ sender: NSButton) {
        repeatHighlight = sender.tag
        let types = ["none", "daily", "weekly", "monthly", "yearly"]
        if sender.tag == 5 {
            custom = Logic.customDraft(from: rule, start: startDate())
            showCustom()
        } else {
            rule = RepeatRule.preset(types[sender.tag])
            showForm()
        }
    }

    private func showCustom() {
        page = "custom"
        container.subviews.forEach { $0.removeFromSuperview() }
        let close = NSButton(title: "×", target: self, action: #selector(openRepeats))
        close.isBordered = false
        close.font = .systemFont(ofSize: 20)
        let title = NSTextField(labelWithString: "自定义")
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        let ok = NSButton(title: "✓", target: self, action: #selector(confirmCustom))
        ok.isBordered = false
        ok.font = .systemFont(ofSize: 20, weight: .bold)
        let bar = NSStackView(views: [close, title, ok])
        bar.orientation = .horizontal
        bar.distribution = .equalSpacing
        customInterval.columns = [
            .init(title: "", values: Array(1...99), loop: true, value: custom.interval, label: { "\($0)" }),
            .init(title: "", values: Array(0...3), loop: false, value: Logic.units.firstIndex(of: custom.unit) ?? 1, label: { Logic.unitLabels[$0] })
        ]
        customInterval.onChange = { [weak self] in self?.readCustomWheels() }
        let summary = NSTextField(labelWithString: "重复类型          \(Logic.everyLabel(interval: custom.interval, unitIndex: Logic.units.firstIndex(of: custom.unit) ?? 1))")
        summary.font = .systemFont(ofSize: 15)
        let card = NSStackView(views: [summary, customInterval])
        card.orientation = .vertical
        card.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 8, right: 12)
        card.wantsLayer = true
        card.layer?.backgroundColor = Chrome.card.cgColor
        card.layer?.cornerRadius = 16
        customInterval.translatesAutoresizingMaskIntoConstraints = false
        customInterval.widthAnchor.constraint(equalToConstant: 400).isActive = true
        customInterval.heightAnchor.constraint(equalToConstant: 180).isActive = true
        let weekCard = NSStackView()
        weekCard.orientation = .vertical
        weekCard.spacing = 0
        weekCard.wantsLayer = true
        weekCard.layer?.backgroundColor = Chrome.card.cgColor
        weekCard.layer?.cornerRadius = 16
        for day in 0..<7 {
            let button = NSButton(title: Logic.weekdayLong[day], target: self, action: #selector(toggleWeekday(_:)))
            button.tag = day
            button.alignment = .left
            button.isBordered = false
            button.bezelStyle = .shadowlessSquare
            if custom.weekdays.contains(day) { button.title = "\(Logic.weekdayLong[day])          ✓" }
            button.contentTintColor = custom.weekdays.contains(day) ? Chrome.orange : .labelColor
            weekCard.addArrangedSubview(button)
            button.heightAnchor.constraint(equalToConstant: 36).isActive = true
            button.widthAnchor.constraint(equalToConstant: 400).isActive = true
        }
        weekCard.isHidden = custom.unit != "week"
        weekCard.identifier = NSUserInterfaceItemIdentifier("weekdays")
        let untilButton = NSButton(title: "有效日期          \(custom.endMode == "until" ? (custom.until ?? "指定日期") : "一直")", target: self, action: #selector(cycleUntil))
        untilButton.isBordered = false
        untilButton.alignment = .left
        let untilCard = NSStackView(views: [untilButton])
        untilCard.orientation = .vertical
        untilCard.wantsLayer = true
        untilCard.layer?.backgroundColor = Chrome.card.cgColor
        untilCard.layer?.cornerRadius = 16
        untilCard.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        if custom.endMode == "until" {
            let date = custom.until.flatMap(Logic.parse) ?? Logic.addDays(startDate(), 365)
            untilWheel.columns = [
                .init(title: "年", values: Array(1970...2100), loop: false, value: Logic.component(date, .year), label: { "\($0)" }),
                .init(title: "月", values: Array(1...12), loop: true, value: Logic.component(date, .month), label: { "\($0)" }),
                .init(title: "日", values: Array(1...31), loop: true, value: Logic.component(date, .day), label: { "\($0)" })
            ]
            untilWheel.onChange = { [weak self] in self?.readUntil() }
            untilCard.addArrangedSubview(untilWheel)
            untilWheel.translatesAutoresizingMaskIntoConstraints = false
            untilWheel.widthAnchor.constraint(equalToConstant: 400).isActive = true
            untilWheel.heightAnchor.constraint(equalToConstant: 210).isActive = true
        }
        let stack = NSStackView(views: [bar, card, weekCard, untilCard, secondary("数字和日/周/月/年可用上下键调整，左右键切换列", size: 12)])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 16, right: 16)
        mount(stack)
        window.makeFirstResponder(customInterval)
    }

    @objc private func toggleWeekday(_ sender: NSButton) {
        weekdayHighlight = sender.tag
        if custom.weekdays.contains(sender.tag) { custom.weekdays.removeAll { $0 == sender.tag } }
        else { custom.weekdays.append(sender.tag); custom.weekdays.sort() }
        showCustom()
    }

    @objc private func cycleUntil() {
        if custom.endMode == "until" {
            custom.endMode = "forever"
            custom.until = nil
        } else {
            custom.endMode = "until"
            custom.until = Logic.format(Logic.addDays(startDate(), 365), time: false)
        }
        showCustom()
    }

    @objc private func confirmCustom() {
        readCustomWheels()
        if custom.unit == "week" && custom.weekdays.isEmpty {
            conflictLabel.stringValue = "请至少选择一天"
            showCustom()
            return
        }
        custom.type = "custom"
        rule = custom
        showForm()
    }

    private func readCustomWheels() {
        guard customInterval.columns.count == 2 else { return }
        custom.interval = customInterval.columns[0].value
        custom.unit = Logic.units[min(max(customInterval.columns[1].value, 0), 3)]
    }

    private func readUntil() {
        guard untilWheel.columns.count == 3 else { return }
        let date = Logic.compose(year: untilWheel.columns[0].value, month: untilWheel.columns[1].value, day: untilWheel.columns[2].value)
        custom.until = Logic.format(date, time: false)
    }

    @objc private func showFormAction() { showForm() }
    @objc private func allDayChanged() {
        let on = allDaySwitch.state == .on
        configureDateWheel(startWheel, time: !on)
        configureDateWheel(endWheel, time: !on)
        if endLinked { applyLinkedEnd() }
        showForm()
    }

    private func startChanged() {
        clampDay(startWheel)
        if endLinked { applyLinkedEnd() }
        refreshConflict()
    }

    private func applyLinkedEnd() {
        let end = Logic.defaultEnd(start: startDate(), allDay: allDaySwitch.state == .on)
        setWheel(endWheel, raw: Logic.format(end, time: allDaySwitch.state == .off), time: allDaySwitch.state == .off)
    }

    private func refreshConflict() {
        let titles = Logic.conflicts(for: draft(), among: store.database.events)
        conflictLabel.stringValue = titles.isEmpty ? "" : "有冲突：\(titles.joined(separator: "、"))"
        conflictLabel.textColor = Chrome.orange
    }

    @objc private func saveEvent() {
        let name = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        guard endDate() > startDate() || (allDaySwitch.state == .on && Logic.startOfDay(endDate()) >= Logic.startOfDay(startDate())) else {
            conflictLabel.stringValue = "结束时间需要晚于开始时间"
            return
        }
        var event = draft()
        event.title = name
        if existingID == nil { event.id = UUID() }
        store.upsertEvent(event)
        dismissEditor()
    }

    @objc private func deleteEvent() {
        guard let existingID, let event = store.database.events.first(where: { $0.id == existingID }) else { return }
        if event.repeatRule.type != "none" {
            let alert = NSAlert()
            alert.messageText = "删除重复日程"
            alert.informativeText = "选择删除这一次，或删除这组重复日程。"
            alert.addButton(withTitle: "删除本日程")
            alert.addButton(withTitle: "删除重复的所有日程")
            alert.addButton(withTitle: "取消")
            let day = occurrence ?? Logic.parse(event.start) ?? Date()
            alert.beginSheetModal(for: window) { [weak self] response in
                guard let self else { return }
                switch response {
                case .alertFirstButtonReturn:
                    self.store.excludeEventDay(existingID, day: day)
                case .alertSecondButtonReturn:
                    self.store.deleteEvent(existingID)
                default:
                    return
                }
                self.dismissEditor()
            }
            return
        }
        store.deleteEvent(existingID)
        dismissEditor()
    }

    private func dismissEditor() {
        window.orderOut(nil)
        window.close()
    }

    private func draft() -> ScheduleEvent {
        let allDay = allDaySwitch.state == .on
        return ScheduleEvent(
            id: existingID ?? UUID(),
            title: titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notesField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            allDay: allDay,
            start: Logic.format(startDate(), time: !allDay),
            end: Logic.format(allDay ? Logic.startOfDay(endDate()) : endDate(), time: !allDay),
            repeatRule: rule,
            createdAt: createdAt,
            updatedAt: Logic.nowStamp(),
            excludedDates: store.database.events.first { $0.id == existingID }?.excludedDates ?? []
        )
    }

    private func startDate() -> Date { date(from: startWheel, allDay: allDaySwitch.state == .on) }
    private func endDate() -> Date { date(from: endWheel, allDay: allDaySwitch.state == .on) }

    private func date(from wheel: WheelControl, allDay: Bool) -> Date {
        let cols = wheel.columns
        guard cols.count >= 3 else { return Date() }
        return Logic.compose(year: cols[0].value, month: cols[1].value, day: cols[2].value, hour: allDay || cols.count < 5 ? 0 : cols[3].value, minute: allDay || cols.count < 5 ? 0 : cols[4].value)
    }

    private func configureDateWheel(_ wheel: WheelControl, time: Bool) {
        let current = wheel.columns.count >= 3 ? date(from: wheel, allDay: !time) : Date()
        setWheel(wheel, raw: Logic.format(current, time: time), time: time)
    }

    private func setWheel(_ wheel: WheelControl, raw: String, time: Bool) {
        let date = Logic.parse(raw) ?? Date()
        var columns = [
            WheelControl.Column(title: "年", values: Array(1970...2100), loop: false, value: Logic.component(date, .year), label: { "\($0)" }),
            WheelControl.Column(title: "月", values: Array(1...12), loop: true, value: Logic.component(date, .month), label: { "\($0)" }),
            WheelControl.Column(title: "日", values: Array(1...Logic.daysInMonth(year: Logic.component(date, .year), month: Logic.component(date, .month))), loop: true, value: Logic.component(date, .day), label: { "\($0)" })
        ]
        if time {
            columns.append(.init(title: "时", values: Array(0...23), loop: true, value: Logic.component(date, .hour), label: { String(format: "%02d", $0) }))
            columns.append(.init(title: "分", values: Array(0...59), loop: true, value: Logic.component(date, .minute), label: { String(format: "%02d", $0) }))
        }
        wheel.columns = columns
    }

    private func clampDay(_ wheel: WheelControl) {
        guard wheel.columns.count >= 3 else { return }
        var columns = wheel.columns
        let maxDay = Logic.daysInMonth(year: columns[0].value, month: columns[1].value)
        columns[2].values = Array(1...maxDay)
        columns[2].value = min(columns[2].value, maxDay)
        wheel.columns = columns
    }

    private func editorHeader(_ title: String, save: String, action: Selector) -> NSView {
        let cancel = NSButton(title: "取消", target: self, action: #selector(close))
        cancel.isBordered = false
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        let done = NSButton(title: save, target: self, action: action)
        done.isBordered = false
        done.contentTintColor = Chrome.green
        let bar = NSStackView(views: [cancel, label, done])
        bar.orientation = .horizontal
        bar.distribution = .equalSpacing
        return bar
    }

    @objc private func close() { dismissEditor() }

    private func mount(_ stack: NSStackView) {
        embedForm(stack, in: container)
        window.setContentSize(NSSize(width: max(window.frame.width, 480), height: max(window.frame.height, 760)))
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        if page == "repeats" {
            switch event.keyCode {
            case 125: repeatHighlight = min(5, repeatHighlight + 1); openRepeats(); return true
            case 126: repeatHighlight = max(0, repeatHighlight - 1); openRepeats(); return true
            case 36, 76:
                let types = ["none", "daily", "weekly", "monthly", "yearly"]
                if repeatHighlight == 5 { custom = Logic.customDraft(from: rule, start: startDate()); showCustom() }
                else { rule = RepeatRule.preset(types[repeatHighlight]); showForm() }
                return true
            default: return false
            }
        }
        let weekdayKeys: Set<UInt16> = [49, 125, 126]
        if page == "custom", weekdayKeys.contains(event.keyCode), custom.unit == "week", window.firstResponder !== customInterval, window.firstResponder !== untilWheel {
            if event.keyCode == 125 { weekdayHighlight = min(6, weekdayHighlight + 1) }
            if event.keyCode == 126 { weekdayHighlight = max(0, weekdayHighlight - 1) }
            if event.keyCode == 49 {
                if custom.weekdays.contains(weekdayHighlight) { custom.weekdays.removeAll { $0 == weekdayHighlight } }
                else { custom.weekdays.append(weekdayHighlight); custom.weekdays.sort() }
            }
            showCustom()
            return true
        }
        return false
    }
}

final class ReminderEditorWindow: NSObject, NSWindowDelegate {
    let window: NSWindow
    var onClose: (() -> Void)?
    private let store: Store
    let existingID: UUID?
    private var titleField = NSTextField()
    private var notesField = NSTextField()
    private let dueSwitch = NSSwitch()
    private let wheel = WheelControl()
    private let priority = NSSegmentedControl(labels: ["无", "低", "中", "高"], trackingMode: .selectOne, target: nil, action: nil)
    private var completed = false
    private var completedAt: String?
    private var createdAt = ""

    init(store: Store, existingID: UUID?) {
        self.store = store
        self.existingID = existingID
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 640), styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init()
        window.title = existingID == nil ? "新建提醒事项" : "编辑提醒事项"
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Chrome.background
        window.level = .modalPanel
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.minSize = NSSize(width: 440, height: 560)
        window.contentMinSize = NSSize(width: 440, height: 560)
        build()
        window.setContentSize(NSSize(width: 460, height: 680))
        window.center()
        wheel.sensitivity = { [weak self] in self?.store.database.preferences.scrollSensitivity ?? 1 }
    }

    func show() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    func windowWillClose(_ notification: Notification) { onClose?() }

    private func build() {
        var due = Logic.nextHour()
        if let existingID, let item = store.database.reminders.first(where: { $0.id == existingID }) {
            titleField.stringValue = item.title
            notesField.stringValue = item.notes
            priority.selectedSegment = item.priority
            completed = item.completed
            completedAt = item.completedAt
            createdAt = item.createdAt
            if let parsed = item.due.flatMap(Logic.parse) { due = parsed; dueSwitch.state = .on }
        } else {
            createdAt = Logic.nowStamp()
            priority.selectedSegment = 0
        }
        setDue(due)
        titleField = styledField(titleField.stringValue, placeholder: "事项名称", size: 22, bold: true)
        notesField = styledField(notesField.stringValue, placeholder: "备注", size: 15, bold: false)
        dueSwitch.target = self
        dueSwitch.action = #selector(rebuild)
        let heading = NSTextField(labelWithString: existingID == nil ? "新建提醒事项" : "编辑提醒事项")
        heading.font = .systemFont(ofSize: 15, weight: .semibold)
        heading.alignment = .center
        wheel.onChange = { [weak self] in self?.clamp() }
        var views: [NSView] = [heading, titleField, notesField, labeledRow("提醒时间", dueSwitch)]
        if dueSwitch.state == .on { views.append(wheel) }
        views.append(priority)
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 18, bottom: 84, right: 18)
        if wheel.constraints.isEmpty {
            wheel.translatesAutoresizingMaskIntoConstraints = false
            wheel.widthAnchor.constraint(equalToConstant: 400).isActive = true
            wheel.heightAnchor.constraint(equalToConstant: 210).isActive = true
        }
        guard let content = window.contentView else { return }
        content.subviews.forEach { $0.removeFromSuperview() }
        embedForm(stack, in: content)
        pinGlassActions(on: content, cancel: #selector(close), save: #selector(save), tint: Chrome.purple, target: self, delete: existingID == nil ? nil : #selector(deleteItem))
    }

    @objc private func rebuild() { build() }
    @objc private func close() { window.orderOut(nil); window.close() }

    @objc private func save() {
        let name = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let due: String? = dueSwitch.state == .on && wheel.columns.count >= 5
            ? Logic.format(Logic.compose(year: wheel.columns[0].value, month: wheel.columns[1].value, day: wheel.columns[2].value, hour: wheel.columns[3].value, minute: wheel.columns[4].value), time: true)
            : nil
        store.upsertReminder(ReminderItem(id: existingID ?? UUID(), title: name, notes: notesField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), due: due, priority: priority.selectedSegment, completed: completed, completedAt: completedAt, createdAt: createdAt, updatedAt: Logic.nowStamp()))
        window.orderOut(nil)
        window.close()
    }

    @objc private func deleteItem() {
        guard let existingID else { return }
        store.deleteReminder(existingID)
        window.orderOut(nil)
        window.close()
    }

    private func setDue(_ date: Date) {
        wheel.columns = [
            .init(title: "年", values: Array(1970...2100), loop: false, value: Logic.component(date, .year), label: { "\($0)" }),
            .init(title: "月", values: Array(1...12), loop: true, value: Logic.component(date, .month), label: { "\($0)" }),
            .init(title: "日", values: Array(1...Logic.daysInMonth(year: Logic.component(date, .year), month: Logic.component(date, .month))), loop: true, value: Logic.component(date, .day), label: { "\($0)" }),
            .init(title: "时", values: Array(0...23), loop: true, value: Logic.component(date, .hour), label: { String(format: "%02d", $0) }),
            .init(title: "分", values: Array(0...59), loop: true, value: Logic.component(date, .minute), label: { String(format: "%02d", $0) })
        ]
    }

    private func clamp() {
        guard wheel.columns.count >= 3 else { return }
        var columns = wheel.columns
        let maxDay = Logic.daysInMonth(year: columns[0].value, month: columns[1].value)
        columns[2].values = Array(1...maxDay)
        columns[2].value = min(columns[2].value, maxDay)
        wheel.columns = columns
    }
}

final class SettingsWindowController: NSObject {
    let window: NSWindow
    private let store: Store
    private let pathLabel = NSTextField(wrappingLabelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")
    private let slider = NSSlider(value: 14, minValue: 12, maxValue: 22, target: nil, action: nil)
    private let sizeLabel = NSTextField(labelWithString: "14")
    private let scrollSlider = NSSlider(value: 1, minValue: 1, maxValue: 5, target: nil, action: nil)
    private let scrollLabel = NSTextField(labelWithString: "低")
    private let sound = NSSwitch()
    private let earlyReminder = NSSwitch()
    private let showDone = NSSwitch()
    private let scheduleOnTop = NSSwitch()
    private let remindersOnTop = NSSwitch()
    private let combinedOnTop = NSSwitch()
    private let cardWell = NSColorWell()
    private let startWell = NSColorWell()
    private let endWell = NSColorWell()
    var onPick: (() -> Void)?
    var onMove: (() -> Void)?
    var onExport: (() -> Void)?
    var onImport: (() -> Void)?
    var onReset: (() -> Void)?

    init(store: Store) {
        self.store = store
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 820), styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init()
        window.title = "设置"
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Chrome.background
        window.level = .normal
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 360, height: 280)
        window.contentMinSize = NSSize(width: 360, height: 280)
        slider.target = self
        slider.action = #selector(fontChanged)
        slider.numberOfTickMarks = 11
        scrollSlider.target = self
        scrollSlider.action = #selector(scrollChanged)
        scrollSlider.numberOfTickMarks = 5
        scrollSlider.allowsTickMarkValuesOnly = true
        sound.target = self
        sound.action = #selector(soundChanged)
        earlyReminder.target = self
        earlyReminder.action = #selector(earlyReminderChanged)
        showDone.target = self
        showDone.action = #selector(showDoneChanged)
        scheduleOnTop.target = self
        scheduleOnTop.action = #selector(scheduleOnTopChanged)
        remindersOnTop.target = self
        remindersOnTop.action = #selector(remindersOnTopChanged)
        combinedOnTop.target = self
        combinedOnTop.action = #selector(combinedOnTopChanged)
        build()
        window.center()
    }

    func show() { reload(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }

    func reload() {
        slider.doubleValue = store.database.preferences.fontSize
        sizeLabel.stringValue = "\(Int(store.database.preferences.fontSize))"
        scrollSlider.doubleValue = store.database.preferences.scrollSensitivity
        scrollLabel.stringValue = Self.scrollName(store.database.preferences.scrollSensitivity)
        sound.state = store.database.preferences.soundEnabled ? .on : .off
        earlyReminder.state = store.database.preferences.earlyReminder ? .on : .off
        showDone.state = store.database.preferences.showCompletedReminders ? .on : .off
        scheduleOnTop.state = store.database.preferences.scheduleOnTop ? .on : .off
        remindersOnTop.state = store.database.preferences.remindersOnTop ? .on : .off
        combinedOnTop.state = store.database.preferences.combinedOnTop ? .on : .off
        cardWell.color = NSColor(hex: store.database.preferences.cardColor) ?? NSColor(hex: Preferences.defaultCardColor)!
        startWell.color = NSColor(hex: store.database.preferences.startColor) ?? NSColor(hex: Preferences.defaultStartColor)!
        endWell.color = NSColor(hex: store.database.preferences.endColor) ?? NSColor(hex: Preferences.defaultEndColor)!
        pathLabel.stringValue = store.dataPath.path
        countLabel.stringValue = "\(store.database.events.count) 个日程 · \(store.database.reminders.count) 个提醒事项"
    }

    private func build() {
        let reminders = settingLine("显示提醒事项组件", "点按圆圈即可完成", switchFor("reminders"))
        let combined = settingLine("显示综合组件", "左侧提醒事项，右侧日程", switchFor("combined"))
        sizeLabel.alignment = .right
        sizeLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        let sample = NSTextField(labelWithString: "示例日程")
        sample.font = .systemFont(ofSize: 14, weight: .medium)
        sample.alignment = .left
        let reset = NSButton(title: "恢复为默认设置", target: self, action: #selector(reset))
        reset.bezelStyle = .rounded
        pathLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.maximumNumberOfLines = 2
        pathLabel.lineBreakMode = .byTruncatingTail
        pathLabel.cell?.wraps = true
        pathLabel.cell?.isScrollable = false
        pathLabel.alignment = .left
        let help = secondary("JSON 文件，macOS 与 Windows 都能读取和导入，包含偏好、日程和提醒事项。", size: 12)
        help.alignment = .left
        help.maximumNumberOfLines = 2
        help.lineBreakMode = .byTruncatingTail
        countLabel.alignment = .left
        let open = NSButton(title: "打开其他数据库", target: self, action: #selector(pick))
        let move = NSButton(title: "保存到新位置", target: self, action: #selector(moveDB))
        let export = NSButton(title: "导出", target: self, action: #selector(exportDB))
        let importButton = NSButton(title: "导入", target: self, action: #selector(importDB))
        let form = SettingsForm(blocks: [
            sectionTitle("日程"),
            settingLine("显示日程组件", "今天、明天、后天，可继续滚动查看之后的日程", switchFor("schedule")),
            settingLine("事项底色", nil, colorWell(cardWell, "card")),
            settingLine("开始时间", nil, colorWell(startWell, "start")),
            settingLine("结束时间", nil, colorWell(endWell, "end")),
            sectionTitle("提醒事项"),
            reminders,
            settingLine("显示已完成", nil, showDone),
            sectionTitle("小组件"),
            combined,
            settingLine("字体大小", nil, sizeLabel),
            fullWidth(slider, height: 28),
            settingLine("滚轮灵敏度", nil, scrollLabel),
            fullWidth(scrollSlider, height: 28),
            plain(sample, height: 22),
            settingLine("", nil, reset),
            sectionTitle("通知"),
            settingLine("提前5分钟提醒", "到点前提示“日程名称马上就要开始了”", earlyReminder),
            settingLine("到点弹窗时播放声音", nil, sound),
            sectionTitle("数据库"),
            wrapping(pathLabel),
            wrapping(help),
            plain(countLabel, height: 20),
            trailing([open, move, export, importButton])
        ])
        guard let content = window.contentView else { return }
        form.autoresizingMask = [.width, .height]
        form.frame = content.bounds
        content.addSubview(form)
        window.setContentSize(NSSize(width: 560, height: 820))
    }

    private func switchFor(_ kind: String) -> NSSwitch {
        let toggle = NSSwitch()
        toggle.state = store.database.preferences.widgets.frame(for: kind).visible ? .on : .off
        toggle.identifier = NSUserInterfaceItemIdentifier(kind)
        toggle.target = self
        toggle.action = #selector(toggleWidget(_:))
        return toggle
    }

    private func colorWell(_ well: NSColorWell, _ key: String) -> NSColorWell {
        well.identifier = NSUserInterfaceItemIdentifier(key)
        well.target = self
        well.action = #selector(colorChanged(_:))
        well.translatesAutoresizingMaskIntoConstraints = false
        well.widthAnchor.constraint(equalToConstant: 44).isActive = true
        well.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return well
    }

    private func sectionTitle(_ text: String) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.alignment = .left
        return plain(label, height: 22)
    }

    private func settingLine(_ title: String, _ detail: String?, _ accessory: NSView) -> NSView {
        SettingLine(title: title, detail: detail, accessory: accessory)
    }

    private func fullWidth(_ control: NSView, height: CGFloat) -> NSView {
        let wrap = NSView()
        control.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(control)
        NSLayoutConstraint.activate([
            control.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            control.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            control.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
            wrap.heightAnchor.constraint(equalToConstant: height)
        ])
        return wrap
    }

    private func wrapping(_ label: NSTextField) -> NSView {
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        label.cell?.wraps = true
        label.cell?.isScrollable = false
        return WrappingBlock(label: label)
    }

    private func plain(_ label: NSView, height: CGFloat) -> NSView {
        label.translatesAutoresizingMaskIntoConstraints = false
        let wrap = NSView()
        wrap.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: wrap.trailingAnchor),
            label.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
            wrap.heightAnchor.constraint(equalToConstant: height)
        ])
        return wrap
    }

    private func trailing(_ controls: [NSView]) -> NSView {
        let row = NSStackView(views: controls)
        row.orientation = .horizontal
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        let wrap = NSView()
        wrap.addSubview(row)
        NSLayoutConstraint.activate([
            row.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            row.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
            wrap.heightAnchor.constraint(equalToConstant: 32)
        ])
        return wrap
    }

    @objc private func colorChanged(_ sender: NSColorWell) {
        let hex = sender.color.hexString
        store.updatePreferences { prefs in
            switch sender.identifier?.rawValue {
            case "start": prefs.startColor = hex
            case "end": prefs.endColor = hex
            default: prefs.cardColor = hex
            }
        }
    }

    @objc private func fontChanged() {
        store.updatePreferences { $0.fontSize = slider.doubleValue.rounded() }
        sizeLabel.stringValue = "\(Int(store.database.preferences.fontSize))"
    }
    @objc private func scrollChanged() {
        store.updatePreferences { $0.scrollSensitivity = scrollSlider.doubleValue.rounded() }
        scrollLabel.stringValue = Self.scrollName(store.database.preferences.scrollSensitivity)
    }
    private static func scrollName(_ value: Double) -> String {
        switch Int(value.rounded()) {
        case 1: return "低"
        case 2: return "较低"
        case 3: return "中"
        case 4: return "较高"
        default: return "高"
        }
    }
    @objc private func soundChanged() { store.updatePreferences { $0.soundEnabled = sound.state == .on } }
    @objc private func earlyReminderChanged() { store.updatePreferences { $0.earlyReminder = earlyReminder.state == .on } }
    @objc private func showDoneChanged() { store.updatePreferences { $0.showCompletedReminders = showDone.state == .on } }
    @objc private func scheduleOnTopChanged() { store.updatePreferences { $0.scheduleOnTop = scheduleOnTop.state == .on } }
    @objc private func remindersOnTopChanged() { store.updatePreferences { $0.remindersOnTop = remindersOnTop.state == .on } }
    @objc private func combinedOnTopChanged() { store.updatePreferences { $0.combinedOnTop = combinedOnTop.state == .on } }
    @objc private func toggleWidget(_ sender: NSSwitch) {
        guard let kind = sender.identifier?.rawValue else { return }
        store.updatePreferences { prefs in
            var frame = prefs.widgets.frame(for: kind)
            frame.visible = sender.state == .on
            prefs.widgets.setFrame(frame, for: kind)
        }
    }
    @objc private func pick() { onPick?() }
    @objc private func moveDB() { onMove?() }
    @objc private func exportDB() { onExport?() }
    @objc private func importDB() { onImport?() }
    @objc private func reset() {
        onReset?()
        reload()
    }
}

final class NoticeWindow: NSObject {
    let window: NSWindow
    private let store: Store
    var onClose: (() -> Void)?
    var onSnooze: (() -> Void)?

    init(store: Store) {
        self.store = store
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 240), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        super.init()
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.level = .popUpMenu
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Chrome.background
    }

    func show(_ notices: [Notice]) {
        guard let content = window.contentView else { return }
        content.subviews.forEach { $0.removeFromSuperview() }
        let heading = NSTextField(labelWithString: notices.contains(where: { $0.kind == "event" }) ? "日程到点" : "提醒事项")
        heading.textColor = .secondaryLabelColor
        var rows: [NSView] = [heading]
        for notice in notices {
            let when = NSTextField(labelWithString: notice.when)
            when.textColor = notice.kind == "event" ? Chrome.green : Chrome.purple
            when.font = .systemFont(ofSize: 13, weight: .semibold)
            let title = NSTextField(labelWithString: notice.title)
            title.font = .systemFont(ofSize: 18, weight: .semibold)
            let column = NSStackView(views: [when, title])
            column.orientation = .vertical
            column.alignment = .leading
            if !notice.notes.isEmpty { column.addArrangedSubview(secondary(notice.notes, size: 13)) }
            if notice.conflict {
                let badge = NSTextField(labelWithString: "有冲突")
                badge.textColor = Chrome.orange
                badge.font = .systemFont(ofSize: 13, weight: .semibold)
                column.addArrangedSubview(badge)
            }
            rows.append(column)
        }
        let sound = NSSwitch()
        sound.state = store.database.preferences.soundEnabled ? .on : .off
        sound.target = self
        sound.action = #selector(toggleSound(_:))
        rows.append(labeledRow("播放声音", sound))
        let ok = NSButton(title: "知道了", target: self, action: #selector(close))
        ok.keyEquivalent = "\r"
        let later = NSButton(title: "5 分钟后", target: self, action: #selector(snooze))
        rows.append(NSStackView(views: [ok, later]))
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor)
        ])
        window.setContentSize(NSSize(width: 360, height: max(200, 90 + notices.count * 70)))
        if let screen = NSScreen.main?.visibleFrame {
            window.setFrameOrigin(NSPoint(x: screen.maxX - window.frame.width - 16, y: screen.maxY - window.frame.height - 16))
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleSound(_ sender: NSSwitch) { store.updatePreferences { $0.soundEnabled = sender.state == .on } }
    @objc private func close() { onClose?() }
    @objc private func snooze() { onSnooze?() }
}

final class FlippedView: NSView { override var isFlipped: Bool { true } }
final class FlippedClipView: NSClipView { override var isFlipped: Bool { true } }

final class ClickCatcher: NSView {
    var action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action; super.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }
    override func mouseDown(with event: NSEvent) { action() }
}

func configurePin(_ button: NSButton, color: NSColor, action: Selector) {
    button.isBordered = false
    button.bezelStyle = .shadowlessSquare
    button.setButtonType(.momentaryChange)
    button.action = action
    button.wantsLayer = true
    button.layer?.cornerRadius = 13
    button.translatesAutoresizingMaskIntoConstraints = false
    button.widthAnchor.constraint(equalToConstant: 52).isActive = true
    button.heightAnchor.constraint(equalToConstant: 26).isActive = true
    stylePin(button, color: color, on: false)
}

func stylePin(_ button: NSButton, color: NSColor, on: Bool) {
    let line = color.withAlphaComponent(on ? 0.55 : 0.32)
    button.layer?.backgroundColor = color.withAlphaComponent(on ? 0.16 : 0.06).cgColor
    button.layer?.borderWidth = 1
    button.layer?.borderColor = line.cgColor
    button.attributedTitle = NSAttributedString(string: "置顶", attributes: [
        .font: NSFont.systemFont(ofSize: 12, weight: .bold),
        .foregroundColor: color.withAlphaComponent(on ? 0.8 : 0.45)
    ])
}

func configureChip(_ button: NSButton, title: String, color: NSColor, action: Selector) {
    button.isBordered = false
    button.bezelStyle = .shadowlessSquare
    button.setButtonType(.momentaryChange)
    button.action = action
    button.wantsLayer = true
    button.layer?.cornerRadius = 13
    button.layer?.backgroundColor = color.withAlphaComponent(0.06).cgColor
    button.layer?.borderWidth = 1
    button.layer?.borderColor = color.withAlphaComponent(0.32).cgColor
    button.attributedTitle = NSAttributedString(string: title, attributes: [
        .font: NSFont.systemFont(ofSize: 12, weight: .bold),
        .foregroundColor: color.withAlphaComponent(0.55)
    ])
    button.translatesAutoresizingMaskIntoConstraints = false
    button.widthAnchor.constraint(equalToConstant: 52).isActive = true
    button.heightAnchor.constraint(equalToConstant: 26).isActive = true
}

final class PlusButton: NSButton {
    var symbolColor = NSColor.white

    override func draw(_ dirtyRect: NSRect) {
        let font = NSFont.systemFont(ofSize: 17, weight: .bold)
        let text = NSAttributedString(string: "+", attributes: [
            .font: font,
            .foregroundColor: symbolColor
        ])
        let line = CTLineCreateWithAttributedString(text)
        guard let run = (CTLineGetGlyphRuns(line) as NSArray).firstObject else { return }
        var glyph = CGGlyph()
        CTRunGetGlyphs(run as! CTRun, CFRange(location: 0, length: 1), &glyph)
        var box = CGRect.zero
        CTFontGetBoundingRectsForGlyphs(font as CTFont, .horizontal, &glyph, &box, 1)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.setFillColor(symbolColor.cgColor)
        ctx.textMatrix = .identity
        ctx.translateBy(x: bounds.midX - box.midX, y: bounds.midY - box.midY)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}

func symbolButton(_ name: String, _ label: String, _ color: NSColor, _ action: Selector) -> NSButton {
    let button = PlusButton()
    button.symbolColor = color
    button.title = ""
    button.bezelStyle = .shadowlessSquare
    button.isBordered = false
    button.wantsLayer = true
    button.layer?.backgroundColor = color.withAlphaComponent(0.1).cgColor
    button.layer?.cornerRadius = 13
    button.layer?.borderWidth = 1
    button.layer?.borderColor = color.withAlphaComponent(0.35).cgColor
    button.action = action
    button.setAccessibilityLabel(label)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.widthAnchor.constraint(equalToConstant: 36).isActive = true
    button.heightAnchor.constraint(equalToConstant: 26).isActive = true
    return button
}

func styledField(_ value: String, placeholder: String, size: CGFloat, bold: Bool) -> NSTextField {
    let field = NSTextField(string: value)
    field.placeholderString = placeholder
    field.isBezeled = false
    field.drawsBackground = false
    field.focusRingType = .none
    field.font = .systemFont(ofSize: size, weight: bold ? .semibold : .regular)
    field.textColor = bold ? .white : .labelColor
    return field
}

extension NSColor {
    convenience init?(hex: String) {
        guard let normalized = Logic.hexColor(hex) else { return nil }
        let body = normalized.dropFirst()
        var value: UInt64 = 0
        guard Scanner(string: String(body)).scanHexInt64(&value) else { return nil }
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255, blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    var hexString: String {
        let color = usingColorSpace(.sRGB) ?? self
        return String(format: "#%02X%02X%02X", Int((color.redComponent * 255).rounded()), Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded()))
    }
}

final class SettingLine: NSView {
    private let text: NSView
    private let accessory: NSView

    init(title: String, detail: String?, accessory: NSView) {
        let name = NSTextField(labelWithString: title)
        name.font = .systemFont(ofSize: 13)
        name.alignment = .left
        name.maximumNumberOfLines = 2
        name.lineBreakMode = .byTruncatingTail
        name.cell?.wraps = true
        name.cell?.isScrollable = false
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        if let detail, !detail.isEmpty {
            let sub = NSTextField(labelWithString: detail)
            sub.font = .systemFont(ofSize: 11)
            sub.textColor = .secondaryLabelColor
            sub.alignment = .left
            sub.maximumNumberOfLines = 2
            sub.lineBreakMode = .byTruncatingTail
            sub.cell?.wraps = true
            sub.cell?.isScrollable = false
            let column = NSStackView(views: [name, sub])
            column.orientation = .vertical
            column.alignment = .leading
            column.spacing = 1
            text = column
        } else {
            text = name
        }
        self.accessory = accessory
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        layer?.cornerRadius = 10
        text.translatesAutoresizingMaskIntoConstraints = false
        accessory.translatesAutoresizingMaskIntoConstraints = false
        addSubview(text)
        addSubview(accessory)
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
            text.trailingAnchor.constraint(lessThanOrEqualTo: accessory.leadingAnchor, constant: -12),
            accessory.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            accessory.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func height(for width: CGFloat) -> CGFloat {
        let textWidth = max(40, width - 28 - 12 - accessory.fittingSize.width)
        if let column = text as? NSStackView {
            for view in column.arrangedSubviews {
                (view as? NSTextField)?.preferredMaxLayoutWidth = textWidth
            }
        } else {
            (text as? NSTextField)?.preferredMaxLayoutWidth = textWidth
        }
        return min(72, max(40, text.fittingSize.height + 16))
    }
}

final class WrappingBlock: NSView {
    private let label: NSTextField

    init(label: NSTextField) {
        self.label = label
        super.init(frame: .zero)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func height(for width: CGFloat) -> CGFloat {
        label.preferredMaxLayoutWidth = width
        return min(36, max(16, label.fittingSize.height))
    }
}

final class SettingsForm: NSView {
    private let scroll = NSScrollView()
    private let document = FlippedView()
    private let blocks: [NSView]

    init(blocks: [NSView]) {
        self.blocks = blocks
        super.init(frame: .zero)
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.documentView = document
        blocks.forEach { document.addSubview($0) }
        addSubview(scroll)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        scroll.frame = bounds
        let width = scroll.contentView.bounds.width
        guard width > 80 else { return }
        let rowWidth = width - 40
        var y: CGFloat = 18
        for block in blocks {
            let height: CGFloat
            if let line = block as? SettingLine {
                height = line.height(for: rowWidth)
            } else if let note = block as? WrappingBlock {
                height = note.height(for: rowWidth)
            } else {
                height = max(block.fittingSize.height, 22)
            }
            block.frame = NSRect(x: 20, y: y, width: rowWidth, height: height)
            y += height + 8
        }
        document.frame = NSRect(x: 0, y: 0, width: width, height: max(y + 20, scroll.contentView.bounds.height))
    }
}

func labeledRow(_ title: String, _ control: NSView) -> NSView {
    let label = NSTextField(labelWithString: title)
    let row = NSStackView(views: [label, NSView(), control])
    row.orientation = .horizontal
    row.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
    row.wantsLayer = true
    row.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.05).cgColor
    row.layer?.cornerRadius = 12
    return row
}

func secondary(_ text: String, size: CGFloat) -> NSTextField {
    let label = NSTextField(wrappingLabelWithString: text)
    label.font = .systemFont(ofSize: size)
    label.textColor = .secondaryLabelColor
    label.maximumNumberOfLines = 3
    label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return label
}

func embedForm(_ stack: NSStackView, in content: NSView) {
    let scroll = NSScrollView()
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    scroll.autoresizingMask = [.width, .height]
    scroll.frame = content.bounds
    let document = FlippedView()
    scroll.documentView = document
    document.translatesAutoresizingMaskIntoConstraints = false
    stack.translatesAutoresizingMaskIntoConstraints = false
    document.addSubview(stack)
    let documentHeight = document.heightAnchor.constraint(equalTo: stack.heightAnchor, constant: 16)
    let fillVisible = document.heightAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.heightAnchor)
    fillVisible.priority = .defaultLow
    NSLayoutConstraint.activate([
        document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
        document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
        document.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
        document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        documentHeight,
        fillVisible,
        stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 8),
        stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 8),
        stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -8)
    ])
    content.addSubview(scroll)
}

func pinGlassActions(on content: NSView, cancel: Selector, save: Selector, tint: NSColor, target: AnyObject, delete: Selector? = nil) {
    let cancelButton = glassButton("取消", tint: NSColor.white.withAlphaComponent(0.88), target: target, action: cancel)
    let saveButton = glassButton("确认", tint: tint.withAlphaComponent(0.95), target: target, action: save)
    content.addSubview(cancelButton)
    content.addSubview(saveButton)
    NSLayoutConstraint.activate([
        cancelButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
        cancelButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
        saveButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
        saveButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16)
    ])
    if let delete {
        let deleteButton = glassButton("删除", tint: NSColor.white.withAlphaComponent(0.88), target: target, action: delete)
        content.addSubview(deleteButton)
        NSLayoutConstraint.activate([
            deleteButton.leadingAnchor.constraint(equalTo: cancelButton.trailingAnchor, constant: 10),
            deleteButton.bottomAnchor.constraint(equalTo: cancelButton.bottomAnchor)
        ])
    }
}

final class GlassButton: NSVisualEffectView {
    let button = NSButton()

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return bounds.contains(local) ? button : nil
    }
}

func glassButton(_ title: String, tint: NSColor, target: AnyObject, action: Selector) -> NSView {
    let effect = GlassButton()
    effect.material = .hudWindow
    effect.blendingMode = .withinWindow
    effect.state = .active
    effect.wantsLayer = true
    effect.layer?.cornerRadius = 18
    effect.layer?.masksToBounds = true
    effect.layer?.borderWidth = 1
    effect.layer?.borderColor = NSColor(white: 0.72, alpha: 0.85).cgColor
    effect.translatesAutoresizingMaskIntoConstraints = false
    let button = effect.button
    button.target = target
    button.action = action
    button.isBordered = false
    button.wantsLayer = true
    button.layer?.backgroundColor = NSColor.clear.cgColor
    button.attributedTitle = NSAttributedString(string: title, attributes: [
        .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
        .foregroundColor: tint
    ])
    button.translatesAutoresizingMaskIntoConstraints = false
    effect.addSubview(button)
    NSLayoutConstraint.activate([
        effect.widthAnchor.constraint(equalToConstant: 108),
        effect.heightAnchor.constraint(equalToConstant: 36),
        button.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
        button.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
        button.topAnchor.constraint(equalTo: effect.topAnchor),
        button.bottomAnchor.constraint(equalTo: effect.bottomAnchor)
    ])
    return effect
}

func group(_ text: String) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = .systemFont(ofSize: 12, weight: .semibold)
    label.textColor = .secondaryLabelColor
    return label
}
