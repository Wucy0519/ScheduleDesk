import SwiftUI

struct WheelBank: View {
    struct Column: Identifiable {
        let id: String
        let title: String
        let values: [Int]
        var loop: Bool
        var label: (Int) -> String
        var value: Binding<Int>
    }

    var columns: [Column]
    var onInteract: () -> Void
    @State private var selected = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 6) {
            if columns.contains(where: { !$0.title.isEmpty }) {
                HStack(spacing: 0) {
                    ForEach(columns) { column in
                        Text(column.title)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(focused ? 0.12 : 0.08))
                    .frame(height: 36)
                    .overlay {
                        if focused {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color(red: 1, green: 0.42, blue: 0.24).opacity(0.7), lineWidth: 1)
                        }
                    }
                HStack(spacing: 0) {
                    ForEach(Array(columns.enumerated()), id: \.element.id) { index, column in
                        columnView(column, index: index)
                    }
                }
            }
            .frame(height: 180)
        }
        .focusable()
        .focused($focused)
        .onKeyPress(.upArrow) { step(-1); return .handled }
        .onKeyPress(.downArrow) { step(1); return .handled }
        .onKeyPress(.leftArrow) { move(-1); return .handled }
        .onKeyPress(.rightArrow) { move(1); return .handled }
        .accessibilityElement(children: .contain)
    }

    private func columnView(_ column: Column, index: Int) -> some View {
        VStack(spacing: 0) {
            ForEach(-2...2, id: \.self) { offset in
                let text = label(column, offset: offset)
                Text(text ?? " ")
                    .font(.system(size: offset == 0 ? 22 : 16, weight: offset == 0 ? .semibold : .regular))
                    .foregroundStyle(offset == 0 ? Color(red: 1, green: 0.42, blue: 0.24) : Color.white.opacity(abs(offset) == 1 ? 0.55 : 0.28))
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selected = index
                        focused = true
                        if offset != 0 { step(offset) }
                    }
            }
        }
        .accessibilityLabel(column.title.isEmpty ? column.label(column.value.wrappedValue) : "\(column.title) \(column.label(column.value.wrappedValue))")
    }

    private func label(_ column: Column, offset: Int) -> String? {
        guard let index = column.values.firstIndex(of: column.value.wrappedValue) ?? column.values.indices.first else { return nil }
        let target = index + offset
        if column.loop {
            let count = column.values.count
            let wrapped = ((target % count) + count) % count
            return column.label(column.values[wrapped])
        }
        guard column.values.indices.contains(target) else { return nil }
        return column.label(column.values[target])
    }

    private func step(_ delta: Int) {
        guard columns.indices.contains(selected) else { return }
        let column = columns[selected]
        guard let index = column.values.firstIndex(of: column.value.wrappedValue) else { return }
        let count = column.values.count
        let target = index + delta
        let next: Int
        if column.loop {
            next = column.values[((target % count) + count) % count]
        } else if column.values.indices.contains(target) {
            next = column.values[target]
        } else {
            return
        }
        column.value.wrappedValue = next
        onInteract()
    }

    private func move(_ delta: Int) {
        focused = true
        selected = min(max(selected + delta, 0), columns.count - 1)
    }
}

struct DateWheels: View {
    @Binding var year: Int
    @Binding var month: Int
    @Binding var day: Int
    @Binding var hour: Int
    @Binding var minute: Int
    var showsTime: Bool
    var onInteract: () -> Void

    var body: some View {
        WheelBank(columns: columns, onInteract: {
            day = min(day, Logic.daysInMonth(year: year, month: month))
            onInteract()
        })
    }

    private var columns: [WheelBank.Column] {
        var items = [
            WheelBank.Column(id: "y", title: "年", values: Array(1970...2100), loop: false, label: { "\($0)" }, value: $year),
            WheelBank.Column(id: "m", title: "月", values: Array(1...12), loop: true, label: { "\($0)" }, value: $month),
            WheelBank.Column(id: "d", title: "日", values: Array(1...Logic.daysInMonth(year: year, month: month)), loop: true, label: { "\($0)" }, value: $day)
        ]
        if showsTime {
            items.append(WheelBank.Column(id: "h", title: "时", values: Array(0...23), loop: true, label: { String(format: "%02d", $0) }, value: $hour))
            items.append(WheelBank.Column(id: "min", title: "分", values: Array(0...59), loop: true, label: { String(format: "%02d", $0) }, value: $minute))
        }
        return items
    }
}
