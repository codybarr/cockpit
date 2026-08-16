// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Cockpit",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Cockpit", targets: ["Cockpit"]),
    ],
    targets: [
        .executableTarget(
            name: "Cockpit",
            linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("Carbon")]
        ),
        .testTarget(name: "CockpitTests", dependencies: ["Cockpit"]),
    ]
)
