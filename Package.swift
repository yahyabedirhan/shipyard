// swift-tools-version: 6.0
import PackageDescription

// ShipyardCore holds every rule and builds on Linux, where agents develop it.
// The Shipyard app target uses Apple-only frameworks, so it only exists on macOS:
// `swift build` and `swift test` on Linux never see it.
var targets: [Target] = [
    .target(
        name: "ShipyardCore",
        dependencies: [.product(name: "TOMLDecoder", package: "TOMLDecoder")],
        path: "Sources/ShipyardCore"
    ),
    .testTarget(
        name: "ShipyardCoreTests",
        dependencies: ["ShipyardCore", .product(name: "TOMLDecoder", package: "TOMLDecoder")],
        path: "Tests/ShipyardCoreTests"
    ),
]

#if os(macOS)
targets.append(
    .executableTarget(
        name: "Shipyard",
        dependencies: ["ShipyardCore"],
        path: "Sources/Shipyard"
    )
)
#endif

let package = Package(
    name: "Shipyard",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ShipyardCore", targets: ["ShipyardCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/dduan/TOMLDecoder", from: "0.4.5"),
    ],
    targets: targets
)
