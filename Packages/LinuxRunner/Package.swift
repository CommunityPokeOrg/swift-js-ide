// swift-tools-version: 5.10
import PackageDescription

// Linux testing/rendering path for PokeIDE.
//
// Reuses the shared EditorCore package (tokenizer, themes, models, engine
// protocol) and renders the IDE UI with SwiftCrossUI's GTK backend.
// JavaScript is executed by a `node` subprocess (JavaScriptCore is not
// available on Linux); see README.md for limitations.
let package = Package(
    name: "LinuxRunner",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../EditorCore"),
        .package(
            url: "https://github.com/stackotter/swift-cross-ui.git",
            revision: "3c696597df857742c9d494768690d6d81d54215a"
        )
    ],
    targets: [
        .executableTarget(
            name: "PokeIDELinux",
            dependencies: [
                .product(name: "EditorCore", package: "EditorCore"),
                .product(name: "SwiftCrossUI", package: "swift-cross-ui"),
                .product(name: "DefaultBackend", package: "swift-cross-ui"),
                .product(name: "GtkBackend", package: "swift-cross-ui")
            ]
        )
    ]
)
