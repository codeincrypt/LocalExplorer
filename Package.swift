// swift-tools-version:5.9
//
// Local Explorer — native, offline macOS file manager.
//
// Layout:
//   ExplorerCore      Foundation-only logic (model, enumeration, sorting, filtering,
//                     navigation, selection, command table, file operations,
//                     persistence). Builds and tests on macOS and Linux.
//   LocalExplorer     SwiftUI + AppKit application (macOS only).
//   ExplorerCoreTests Unit and integration tests for ExplorerCore.
//
// The application target is only declared when the manifest is evaluated on macOS so
// the core can still be built and tested on other platforms (for example CI on Linux).

import PackageDescription

var products: [Product] = [
    .library(name: "ExplorerCore", targets: ["ExplorerCore"]),
]

var targets: [Target] = [
    .target(
        name: "ExplorerCore",
        path: "Sources/ExplorerCore"
    ),
    .testTarget(
        name: "ExplorerCoreTests",
        dependencies: ["ExplorerCore"],
        path: "Tests/ExplorerCoreTests"
    ),
]

#if os(macOS)
products.append(.executable(name: "LocalExplorer", targets: ["LocalExplorer"]))
targets.append(
    .executableTarget(
        name: "LocalExplorer",
        dependencies: ["ExplorerCore"],
        path: "Sources/LocalExplorer",
        linkerSettings: [
            .linkedFramework("AppKit"),
            .linkedFramework("QuickLookThumbnailing"),
            .linkedFramework("Quartz"),
            .linkedFramework("AVFoundation"),
            .linkedFramework("AVKit"),
            .linkedFramework("PDFKit"),
        ]
    )
)
#endif

let package = Package(
    name: "LocalExplorer",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)
