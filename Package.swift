// swift-tools-version: 6.0
import PackageDescription

// ShipyardCore holds every rule and builds on Linux, where agents develop it.
// The ShipyardApp target (the `Shipyard` executable) uses Apple-only
// frameworks, so it only exists on macOS: `swift build` and `swift test` on
// Linux never see it. The app module isn't named `Shipyard` because that's the
// core's orchestrator class.
var targets: [Target] = [
    .target(
        name: "ShipyardCore",
        dependencies: [.product(name: "TOMLDecoder", package: "TOMLDecoder")],
        path: "Sources/ShipyardCore"
    ),
    .testTarget(
        name: "ShipyardCoreTests",
        dependencies: ["ShipyardCore", .product(name: "TOMLDecoder", package: "TOMLDecoder")],
        path: "Tests/ShipyardCoreTests",
        // Recorded GitHub responses, read from the source tree by `StubHTTP.Answer.fixture`.
        exclude: ["Fixtures"]
    ),
]

var products: [Product] = [
    .library(name: "ShipyardCore", targets: ["ShipyardCore"]),
]

#if os(macOS)
targets.append(
    .executableTarget(
        name: "ShipyardApp",
        dependencies: ["ShipyardCore"],
        path: "Sources/ShipyardApp"
    )
)
products.append(.executable(name: "Shipyard", targets: ["ShipyardApp"]))
#endif

let package = Package(
    name: "Shipyard",
    platforms: [.macOS(.v14)],
    products: products,
    dependencies: [
        .package(url: "https://github.com/dduan/TOMLDecoder", from: "0.4.5"),
    ],
    targets: targets
)
