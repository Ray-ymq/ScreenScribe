// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ScreenScribe",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ScreenScribeCore", targets: ["ScreenScribeCore"]),
        .executable(name: "ScreenScribeCoreChecks", targets: ["ScreenScribeCoreChecks"])
    ],
    targets: [
        .target(
            name: "ScreenScribeCore",
            path: "ScreenScribe",
            exclude: [
                "App",
                "MenuBar",
                "Views",
                "Settings",
                "SourcePicker",
                "ScreenScribe.entitlements"
            ],
            sources: [
                "Core",
                "AudioCapture",
                "AudioProcessing",
                "Transcription",
                "TranscriptProcessing",
                "SessionStorage",
                "Recovery",
                "Export"
            ]
        ),
        .testTarget(
            name: "ScreenScribeCoreTests",
            dependencies: ["ScreenScribeCore"],
            path: "Tests/ScreenScribeCoreTests"
        ),
        .executableTarget(
            name: "ScreenScribeCoreChecks",
            dependencies: ["ScreenScribeCore"],
            path: "Checks"
        )
    ]
)
