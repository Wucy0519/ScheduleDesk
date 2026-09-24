import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: Store
    var onPickDatabase: () -> Void
    var onMoveDatabase: () -> Void
    var onExport: () -> Void
    var onImport: () -> Void
    var onResetFrames: () -> Void
    @State private var message = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("设置").font(.system(size: 28, weight: .bold)).padding(.top, 12)
                section("小组件") {
                    widgetToggle("日程组件", detail: "今天、明天、后天，可继续滚动查看之后的日程", kind: "schedule")
                    widgetToggle("提醒事项组件", detail: "点按圆圈即可完成", kind: "reminders")
                    widgetToggle("综合组件", detail: "左侧提醒事项，右侧日程", kind: "combined")
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("字体大小")
                            Spacer()
                            Text("\(Int(store.database.preferences.fontSize))").foregroundStyle(.secondary)
                        }
                        Slider(value: fontSize, in: 12...22, step: 1)
                        Text("示例日程")
                            .font(.system(size: store.database.preferences.fontSize, weight: .medium))
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    Button("重置小组件位置", action: onResetFrames).buttonStyle(.plain).foregroundStyle(.cyan).padding(12)
                }
                section("通知") {
                    Toggle("到点弹窗时播放声音", isOn: sound)
                        .toggleStyle(.switch)
                        .padding(12)
                }
                section("数据库") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(store.dataPath.path)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                        Text("JSON 文件，macOS 与 Windows 都能读取和导入，包含偏好、日程和提醒事项。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text("\(store.database.events.count) 个日程 · \(store.database.reminders.count) 个提醒事项")
                            .font(.system(size: 12))
                        HStack {
                            Button("打开其他数据库", action: onPickDatabase)
                            Button("保存到新位置", action: onMoveDatabase)
                        }
                        HStack {
                            Button("导出", action: onExport)
                            Button("导入", action: onImport)
                        }
                        if !message.isEmpty {
                            Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(minWidth: 520, minHeight: 640)
        .background(WidgetChrome.background)
        .preferredColorScheme(.dark)
    }

    private var fontSize: Binding<Double> {
        Binding(get: { store.database.preferences.fontSize }, set: { value in
            store.updatePreferences { $0.fontSize = value }
        })
    }

    private var sound: Binding<Bool> {
        Binding(get: { store.database.preferences.soundEnabled }, set: { value in
            store.updatePreferences { $0.soundEnabled = value }
        })
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary).padding(.horizontal, 4).padding(.bottom, 6)
            VStack(alignment: .leading, spacing: 0, content: content)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func widgetToggle(_ title: String, detail: String, kind: String) -> some View {
        Toggle(isOn: visibility(kind)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .padding(12)
    }

    private func visibility(_ kind: String) -> Binding<Bool> {
        Binding(
            get: { store.database.preferences.widgets.frame(for: kind).visible },
            set: { value in
                store.updatePreferences { prefs in
                    var frame = prefs.widgets.frame(for: kind)
                    frame.visible = value
                    prefs.widgets.setFrame(frame, for: kind)
                }
            }
        )
    }
}
