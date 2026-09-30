// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SpaceLabels",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SpaceLabelsCore", targets: ["SpaceLabelsCore"]),
        .executable(name: "SpaceLabels", targets: ["SpaceLabels"])
    ],
    targets: [
        .target(name: "SpaceLabelsCore"),
        .executableTarget(
            name: "SpaceLabels",
            dependencies: ["SpaceLabelsCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ColorSync"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .testTarget(name: "SpaceLabelsCoreTests", dependencies: ["SpaceLabelsCore"])
    ]
)
