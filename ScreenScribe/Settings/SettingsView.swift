import Foundation
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        Form {
            Picker("默认模型", selection: $model.defaultModel) {
                Text("多语言 Small（约 486 MB）").tag(ModelDescriptor.small)
                Text("多语言 Medium（约 1.53 GB）").tag(ModelDescriptor.medium)
            }

            Section("本地模型") {
                modelRow(.small)
                modelRow(.medium)
            }

            Toggle("保留原始音频", isOn: $model.keepOriginalAudio)

            TextField("术语提示词", text: $model.terminologyPrompt, axis: .vertical)
                .lineLimit(3...6)

            LabeledContent("模型位置", value: "Application Support/ScreenScribe/Models")

            Text("模型首次下载需要联网，下载完成后转写完全在本地运行。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
    }

    @ViewBuilder
    private func modelRow(_ descriptor: ModelDescriptor) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(descriptor.displayName)
                Text(ByteCountFormatter.string(fromByteCount: descriptor.approximateBytes, countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let progress = model.modelDownloadProgress[descriptor.id] {
                ProgressView(value: progress)
                    .frame(width: 110)
            } else if model.installedModelIDs.contains(descriptor.id) {
                Button("删除") { model.deleteModel(descriptor) }
                    .disabled(model.defaultModel == descriptor)
            } else {
                Button("下载") { model.downloadModel(descriptor) }
            }
        }
    }
}
