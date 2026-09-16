// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EditorCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "EditorCore", targets: ["EditorCore"])
    ],
    targets: [
        .target(
            name: "EditorCore",
            path: "Sources/EditorCore"
        ),
        .testTarget(
            name: "EditorCoreTests",
            dependencies: ["EditorCore"],
            path: "Tests/EditorCoreTests"
        )
    ]
)
