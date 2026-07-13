import SwiftUI

struct MainWindowView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        NavigationSplitView {
            List {
                Section("当前会话") {
                    Label(model.selectedSource?.title ?? "未选择来源", systemImage: "rectangle.on.rectangle")
                    Label(model.defaultModel.displayName, systemImage: "cpu")
                    Label(model.state.rawValue, systemImage: "circle.fill")
                }

                Section("状态") {
                    LabeledContent("音频", value: model.audioLevel.isSilent ? "静音" : "有声音")
                    LabeledContent("实时状态", value: realtimeModeLabel)
                    LabeledContent(
                        "结果延迟",
                        value: String(format: "%.1f 秒", model.realtimeMetrics.submissionToDisplayDuration)
                    )
                    LabeledContent(
                        "排队耗时",
                        value: String(format: "%.1f 秒", model.realtimeMetrics.queueDuration)
                    )
                    LabeledContent("跳过窗口", value: "\(model.realtimeMetrics.skippedWindowCount)")
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 250)
        } detail: {
            VStack(spacing: 0) {
                header
                if let realtimeNotice = model.realtimeNotice {
                    realtimeBanner(realtimeNotice)
                }
                Divider()
                transcript
            }
        }
        .alert("幕语", isPresented: errorPresented) {
            if model.requiresModelDownload {
                Button("打开设置") {
                    model.errorMessage = nil
                    openSettings()
                }
            }
            Button("好", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "未知错误")
        }
    }

    private func realtimeBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: model.realtimeMode == .suspended ? "pause.circle" : "tortoise")
            Text(message)
                .font(.callout)
            Spacer()
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal)
        .padding(.vertical, 9)
        .background(.quaternary.opacity(0.45))
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("实时文稿")
                    .font(.title2.bold())
                Text(model.state == .finalizing ? "正在进行完整音频二次精转" : "临时片段会在停止后由精转结果更新")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.state == .finalizing {
                ProgressView(value: model.finalizationProgress)
                    .frame(width: 160)
            }
        }
        .padding()
    }

    @ViewBuilder
    private var transcript: some View {
        if model.segments.isEmpty {
            ContentUnavailableView(
                "尚无文稿",
                systemImage: "text.bubble",
                description: Text("从菜单栏选择来源并开始录制后，临时文稿会显示在这里。")
            )
        } else {
            List(model.segments) { segment in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(timestamp(segment.startTime))
                            .monospacedDigit()
                        Spacer()
                        Text(statusLabel(segment.status))
                            .foregroundStyle(.secondary)
                    }
                    Text(segment.text)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }

    private func timestamp(_ value: TimeInterval) -> String {
        let seconds = max(0, Int(value))
        return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
    }

    private func statusLabel(_ status: TranscriptSegmentStatus) -> String {
        switch status {
        case .provisional: "临时"
        case .confirmed: "确认"
        case .userEdited: "用户编辑"
        }
    }

    private var realtimeModeLabel: String {
        switch model.realtimeMode {
        case .live: "实时"
        case .throttled: "降频"
        case .suspended: "已暂停"
        }
    }
}
