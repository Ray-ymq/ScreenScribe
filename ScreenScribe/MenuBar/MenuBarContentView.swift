import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("幕语")
                .font(.headline)

            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Menu("选择来源") {
                Button("整屏") { model.choosePlaceholderSource(kind: .display) }
                Button("单窗口") { model.choosePlaceholderSource(kind: .window) }
                Button("单应用") { model.choosePlaceholderSource(kind: .application) }
            }
            .disabled(model.state == .recording || model.state == .paused)

            controls

            Divider()

            Button("打开文稿") { openWindow(id: "transcript") }
            Button("历史会话") { openWindow(id: "transcript") }
            Button("设置…") { openSettings() }

            Divider()

            Button("退出幕语") { NSApplication.shared.terminate(nil) }
        }
        .padding(10)
        .frame(width: 240)
    }

    @ViewBuilder
    private var controls: some View {
        switch model.state {
        case .idle, .completed, .failed:
            Button("开始") { model.start() }
        case .recording:
            Button("暂停") { model.pause() }
            Button("停止") { model.stop() }
        case .paused:
            Button("继续") { model.resume() }
            Button("停止") { model.stop() }
        case .preparing, .finalizing:
            Button("处理中…") {}
                .disabled(true)
        }
    }

    private var statusText: String {
        let source = model.selectedSource?.title ?? "未选择来源"
        return "\(source) · \(model.state.rawValue)"
    }
}

