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

func checkAudioProcessing() throws {
    let stereo48k = [Float](repeating: 0.5, count: 48_000 * 2)
    let mono16k = try PCMProcessor.downmixAndResample(
        interleaved: stereo48k,
        channels: 2,
        inputSampleRate: 48_000
    )
    try require(mono16k.count == 16_000, "48 kHz 立体声未正确转换为 16 kHz 单声道")
    let level = PCMProcessor.level(samples: mono16k)
    try require(!level.isSilent, "非静音音频被识别为静音")

    var planner = AudioWindowPlanner(sampleRate: 10, windowDuration: 10, overlapDuration: 1.5)
    let windows = planner.append([Int16](repeating: 1, count: 185))
    try require(windows.count == 2, "10 秒窗口和 1.5 秒重叠切分错误")
    try require(windows[0].startTime == 0, "首个窗口时间错误")
    try require(windows[1].startTime == 8.5, "重叠窗口时间错误")
}

func checkEditProtection() throws {
    let edited = TranscriptSegment(
        startTime: 2,
        endTime: 4,
        text: "用户修改",
        status: .userEdited
    )
    let refinedConflict = TranscriptSegment(
        startTime: 2.1,
        endTime: 3.9,
        text: "精转覆盖内容",
        status: .provisional
    )
    let refinedSafe = TranscriptSegment(
        startTime: 5,
        endTime: 7,
        text: "安全精转内容",
        status: .provisional
    )
    let result = TranscriptReconciler().reconcile(
        existing: [edited],
        refined: [refinedConflict, refinedSafe]
    )
    try require(result.segments.contains(where: { $0.id == edited.id }), "用户编辑被精转静默覆盖")
    try require(result.segments.contains(where: { $0.text == "安全精转内容" }), "非冲突精转片段未保留")
    try require(result.conflicts.count == 1, "用户编辑冲突未记录")
}

func checkRecoveryPolicy() throws {
    var session = RecordingSession(
        title: "中断会话",
        source: CaptureSourceSelection(id: "display-1", kind: .display, title: "整屏"),
        state: .failed
    )
    let withoutAudio = RecoveryPolicy().candidate(for: session)
    try require(withoutAudio?.availableActions.contains(.resumeFinalization) == false, "无音频会话不应允许恢复精转")
    session.temporaryAudioPath = "/tmp/session.caf"
    let withAudio = RecoveryPolicy().candidate(for: session)
    try require(withAudio?.availableActions.first == .resumeFinalization, "有音频会话应优先恢复精转")
}

do {
    try checkStateMachine()
    try checkExports()
    try checkAudioProcessing()
    try checkEditProtection()
    try checkRecoveryPolicy()
    print("ScreenScribeCoreChecks: 通过")
} catch {
    FileHandle.standardError.write(Data("ScreenScribeCoreChecks: 失败：\(error)\n".utf8))
    exit(1)
}
