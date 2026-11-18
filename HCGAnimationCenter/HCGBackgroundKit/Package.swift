// swift-tools-version:5.7
//
// HCGBackgroundKit — opt-in HCG background preset component (Hakmi Capital Group).
// Add this folder as a local Swift package during development:
//   File › Add Package Dependencies… › Add Local… › HCGAnimationCenter/HCGBackgroundKit
// Objective-C/C target; import with `import HCGBackgroundKit` (Swift) or
// `@import HCGBackgroundKit;` (Objective-C). SwiftPM builds Objective-C with ARC.
import PackageDescription

let package = Package(
    name: "HCGBackgroundKit",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "HCGBackgroundKit", targets: ["HCGBackgroundKit"]),
    ],
    targets: [
        .target(
            name: "HCGBackgroundKit",
            path: "Sources/HCGBackgroundKit",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("UIKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("ImageIO"),
                .linkedFramework("QuartzCore"),
            ]
        ),
    ]
)
