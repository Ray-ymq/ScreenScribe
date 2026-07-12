// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ScreenScribe",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ScreenScribeCore", targets: ["ScreenScribeCore"]),
        .executable(name: "ScreenScribeCoreChecks", targets: ["ScreenScribeCoreChecks"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/argmaxinc/argmax-oss-swift.git",
            from: "1.0.0"
        )
    ],
    targets: [
        .target(
            name: "ScreenScribeCore",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift")
            ],
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
