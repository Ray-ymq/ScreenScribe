import Foundation
import ScreenScribeCore

enum CheckFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case let .failed(message): message
        }
    }
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw CheckFailure.failed(message) }
}

func checkStateMachine() throws {
    var machine = SessionStateMachine()
    try machine.transition(to: .preparing)
    try machine.transition(to: .recording)
    try machine.transition(to: .paused)
    try machine.transition(to: .recording)
    try machine.transition(to: .finalizing)
    try machine.transition(to: .completed)
    try require(machine.state == .completed, "完整状态流程未到达 completed")

    var invalidMachine = SessionStateMachine()
    do {
        try invalidMachine.transition(to: .recording)
        throw CheckFailure.failed("状态机接受了 idle → recording 非法切换")
    } catch is SessionStateError {
        // Expected.
    }
}

func checkExports() throws {
    let session = RecordingSession(
        title: "中文标题",
        source: CaptureSourceSelection(id: "window-1", kind: .window, title: "示例窗口"),
        state: .completed,
        modelID: "small",
        segments: [
            TranscriptSegment(
                startTime: 1.2346,
                endTime: 4.5,
                text: "测试中文文稿",
                status: .confirmed
            )
        ]
    )
    let exporter = DefaultTranscriptExporter()
    let srt = try exporter.render(session: session, format: .srt)
    let text = try exporter.render(session: session, format: .text)
    let markdown = try exporter.render(session: session, format: .markdown)

    try require(srt.contains("00:00:01,235 --> 00:00:04,500"), "SRT 毫秒格式错误")
    try require(text == "测试中文文稿\n", "TXT 内容错误")
    try require(markdown.contains("来源：示例窗口"), "Markdown 缺少来源")
    try require(markdown.contains("[00:00:01]"), "Markdown 缺少时间戳")
}

do {
    try checkStateMachine()
    try checkExports()
    print("ScreenScribeCoreChecks: 通过")
} catch {
    FileHandle.standardError.write(Data("ScreenScribeCoreChecks: 失败：\(error)\n".utf8))
    exit(1)
}

