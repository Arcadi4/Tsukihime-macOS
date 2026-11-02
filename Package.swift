// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tsukihime",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TsukiCore", targets: ["TsukiCore"]),
        .library(name: "TsukiEngine", targets: ["TsukiEngine"]),
        .library(name: "TsukiData", targets: ["TsukiData"]),
        .library(name: "TsukiRender", targets: ["TsukiRender"]),
        .library(name: "TsukiMedia", targets: ["TsukiMedia"]),
        .library(name: "TsukiUi", targets: ["TsukiUi"]),
        .library(name: "TsukiPlatform", targets: ["TsukiPlatform"]),
        .library(name: "TsukiApp", targets: ["TsukiApp"]),
        .executable(name: "Tsukihime", targets: ["Tsukihime"]),
        .executable(name: "tsuki", targets: ["TsukiCli"]),
        .executable(name: "TsukihimeLauncher", targets: ["TsukihimeLauncher"]),
    ],
    targets: [
        .target(name: "TsukiCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "TsukiEngine", dependencies: ["TsukiCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "TsukiData", dependencies: ["TsukiCore", "TsukiEngine"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "TsukiRender", dependencies: ["TsukiCore", "TsukiEngine", "TsukiData"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "TsukiMedia", dependencies: ["TsukiCore", "TsukiEngine", "TsukiData"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "TsukiUi", dependencies: ["TsukiCore", "TsukiEngine", "TsukiData", "TsukiRender"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "TsukiPlatform", dependencies: ["TsukiCore", "TsukiEngine"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "TsukiApp", dependencies: ["TsukiCore", "TsukiEngine", "TsukiData", "TsukiRender", "TsukiMedia", "TsukiUi", "TsukiPlatform"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "Tsukihime", dependencies: ["TsukiApp"], path: "Sources/Tsukihime", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "TsukiCli", dependencies: ["TsukiCore", "TsukiEngine", "TsukiData", "TsukiRender", "TsukiMedia", "TsukiUi", "TsukiPlatform"], path: "Sources/TsukiCli", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(
            name: "TsukihimeLauncher",
            dependencies: ["TsukiCore", "TsukiEngine", "TsukiData", "TsukiPlatform"],
            path: "Sources/TsukiLauncher",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "TsukiCoreTests",
            dependencies: ["TsukiCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "TsukiDataTests",
            dependencies: ["TsukiCore", "TsukiData"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "TsukiRenderTests",
            dependencies: ["TsukiCore", "TsukiEngine", "TsukiData", "TsukiRender"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "TsukiPlatformTests",
            dependencies: ["TsukiCore", "TsukiEngine", "TsukiPlatform"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "TsukiMediaTests",
            dependencies: ["TsukiCore", "TsukiEngine", "TsukiData", "TsukiMedia"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
