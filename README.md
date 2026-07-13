# 幕语 ScreenScribe

幕语是面向 macOS 15+、Apple Silicon 的原生菜单栏系统音频转写应用。

当前开发基线：

- 只捕获所选屏幕、窗口或应用的系统声音，不保存画面。
- 不录制麦克风，也不申请麦克风权限。
- 使用 WhisperKit 完成本地实时转写和停止后的完整音频精转。
- 支持会话恢复、用户编辑保护，以及 Markdown、TXT、SRT 导出。
- 不上架 Mac App Store；发布源码和 ad-hoc 签名的 `.app.zip`。

## 开发要求

- macOS 15+
- Apple Silicon
- Xcode 26.6+
- XcodeGen

## 本地验证

```bash
swift run ScreenScribeCoreChecks
xcodebuild -project ScreenScribe.xcodeproj -scheme ScreenScribe \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
xcodebuild -project ScreenScribe.xcodeproj -scheme ScreenScribe \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO test
```

测试源码会按环境条件导入 SwiftPM 的 `ScreenScribeCore` 或 Xcode App 的
`ScreenScribe` 模块。未安装本地 small 模型时，模型加载集成测试会自动跳过。
