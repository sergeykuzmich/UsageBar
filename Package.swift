// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "usagebar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "usagebar", targets: ["UsageBarApp"]),
        .library(name: "UsageBarCore", targets: ["UsageBarCore"]),
    ],
    targets: [
        .target(name: "UsageBarCore"),
        .executableTarget(
            name: "UsageBarApp",
            dependencies: ["UsageBarCore"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Support/Info.plist",
                ])
            ]
        ),
        .testTarget(name: "UsageBarCoreTests", dependencies: ["UsageBarCore"]),
    ]
)
