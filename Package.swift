// swift-tools-version: 5.10
// SwiftPM manifest. The Xcode project (generated from project.yml) is the
// main build path. This manifest lets `swift build` and `swift test` compile
// the same sources from the command line without Xcode.
import PackageDescription

let package = Package(
    name: "ClipKeeper",
    platforms: [.macOS("15.0")],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.1"),
        .package(url: "https://github.com/raspu/Highlightr", from: "2.3.0"),
        // 1.16.0 added #Preview macros, which the Command Line Tools toolchain cannot expand.
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", "1.10.0"..<"1.16.0"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.11.1"),
    ],
    targets: [
        .executableTarget(
            name: "ClipKeeper",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "Highlightr", package: "Highlightr"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "ClipKeeper",
            exclude: ["Info.plist", "Assets.xcassets"]
        ),
        .testTarget(
            name: "ClipKeeperTests",
            dependencies: ["ClipKeeper"],
            path: "ClipKeeperTests"
        ),
    ]
)
