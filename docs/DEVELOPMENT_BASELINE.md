# 幕语 ScreenScribe 最终开发基线

## MVP 范围

幕语是在 `/Users/ray/Projects/ScreenScribe` 开发的 macOS 15+ 原生菜单栏应用。

- 捕获整屏、单窗口或单应用的系统声音。
- 不保存视频画面。
- 不录制或申请麦克风权限。
- WhisperKit 完全本地转写。
- 录制期间显示实时临时文稿。
- 停止后自动进行完整音频二次精转。
- 保护用户手动修改的内容，冲突时允许保留用户修改、使用精转结果或手动合并。
- 导出 Markdown、TXT、SRT。
- 异常退出、休眠、捕获目标消失、音频流中断或精转退出后恢复会话。
- 发布源代码和可运行 `.app.zip` 到 GitHub，不上架 Mac App Store。

MVP 范围冻结，后续不自行增加功能。

## 技术基线

- SwiftUI + Xcode
- macOS 15+
- Apple Silicon
- Bundle ID：`com.ray.ScreenScribe`
- ScreenCaptureKit 捕获系统音频
- WhisperKit 通过 Swift Package Manager 集成
- 临时音频：16 kHz、单声道、Int16 PCM、CAF
- 本地数据：`~/Library/Application Support/ScreenScribe/`
- 默认模型：多语言 small；可选多语言 medium
- 模型首次联网下载，之后完全离线运行

## 签名与发布约束

项目不依赖 Apple Developer Program：

- 开发构建使用 ad-hoc 签名或关闭代码签名。
- GitHub 发布产物使用 ad-hoc 签名后压缩为 `.app.zip`。
- 不进行 Developer ID 签名和 Apple 公证。
- 用户首次下载运行时需要通过 Finder 右键“打开”确认；无法消除系统对未公证应用的提示。

## 模块

```text
ScreenScribe/
├── App
├── Assets.xcassets
├── Domain
├── Features
│   ├── Capture
│   ├── Export
│   ├── RecordingSessions
│   └── Transcription
├── Presentation
│   ├── MainWindow
│   ├── MenuBar
│   └── Settings
└── ScreenScribe.entitlements

Tests/ScreenScribeCoreTests/
├── Capture
├── Export
├── Integration
├── RecordingSessions
└── Transcription
```

统一状态：`idle → preparing → recording ⇄ paused → finalizing → completed`，任一运行阶段可进入 `failed`，失败会话可恢复精转。

## 音频与转写

- 系统内容选择器提供整屏、窗口、应用来源。
- `SCContentFilter` 排除 ScreenScribe 自身。
- `SCStream` 只处理系统音频，不持久化视频帧。
- 重采样为 16 kHz 单声道 Int16 PCM，计算音量和静音，写入环形缓冲区和临时 CAF。
- 实时默认 10 秒窗口、约 1.5 秒重叠，并根据静音边界优化切分。
- 转写语言默认“自动”，用户可在设置中固定为中文或英文；选择会持久保存，并在每次录制开始时锁定。
- 自动模式在首次有效实时转写时检测并锁定语言；若停止前仍未检测到，则先用完整音频检测。实时窗口与完整音频精转始终复用本次录制的同一明确语言代码。
- Whisper 解码跳过特殊标记，进入文稿前统一清理残留的 `<|...|>` 控制标记并丢弃清理后为空的片段。
- 实时推理落后时降低提交频率；严重积压时停止实时识别但继续保存完整音频。
- 暂停期间不采集、不写入，暂停时间不计入文稿时间轴。
- 停止后对完整音频重新识别，替换未编辑片段并保护用户编辑区间。
- 原始文稿片段及时间戳始终作为持久化数据；界面从片段派生自然段，实时合并并在最终精转后重新整理。
- Markdown、TXT 导出自然段正文，SRT 保持原始片段粒度和时间轴。

## 数据与恢复

```text
~/Library/Application Support/ScreenScribe/
├── Sessions/
├── Models/
└── Exports/
```

每个会话保存元数据、所选转写语言、自动检测后的语言代码、文稿片段、用户编辑状态、冲突、恢复状态、临时音频路径和失败原因。下次启动允许继续精转、打开实时稿或删除会话；缺少语言字段的旧会话按“自动”加载。

## 资源预算

| 项目 | 目标 |
| --- | ---: |
| `.app` 本体 | ≤ 100 MB |
| small 模型 | 约 486 MB |
| medium 模型 | 约 1.53 GB |
| small 实时内存 | ≤ 2 GB |
| small 精转峰值 | ≤ 2.5 GB |
| 待机内存 | ≤ 200 MB |
| 临时音频 | 约 115 MB/小时 |

## 最终验收

- 三种捕获来源均可使用，且不录入 ScreenScribe 自身声音。
- 10 分钟中文视频持续生成文稿，正常实时延迟不超过 5 秒。
- 暂停恢复时间戳正确。
- 精转替换未编辑片段，用户修改不会被静默覆盖。
- 异常中断后能够恢复。
- Markdown、TXT、SRT 格式正确，中文文件名和 UTF-8 正常。
- 默认模型资源占用达到预算。
- GitHub 可以构建并下载可运行 `.app.zip`。
