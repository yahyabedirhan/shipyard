// swift-tools-version: 6.0
import PackageDescription

var targets: [Target] = [
    .target(
        name: "ShipyardCommand",
        path: "Sources/ShipyardCommand"
    ),
    .target(
        name: "ShipyardPings",
        dependencies: ["ShipyardCommand"],
        path: "Sources/ShipyardPings"
    ),
    .target(
        name: "ShipyardCLISettings",
        dependencies: [
            "ShipyardCommand",
            .product(name: "TOMLDecoder", package: "TOMLDecoder"),
        ],
        path: "Sources/ShipyardCLISettings"
    ),
    .target(
        name: "ShipyardNotices",
        dependencies: ["ShipyardCommand", "ShipyardPings", "ShipyardCLISettings"],
        path: "Sources/ShipyardNotices"
    ),
    .target(
        name: "ShipyardConfig",
        dependencies: [
            "ShipyardCommand",
            "ShipyardPings",
            .product(name: "TOMLDecoder", package: "TOMLDecoder"),
        ],
        path: "Sources/ShipyardConfig"
    ),
    .target(
        name: "ShipyardControl",
        dependencies: ["ShipyardCommand", "ShipyardNotices"],
        path: "Sources/ShipyardControl"
    ),
    .target(
        name: "ShipyardCore",
        dependencies: ["ShipyardCommand", "ShipyardPings", "ShipyardNotices", "ShipyardConfig"],
        path: "Sources/ShipyardCore"
    ),
    .testTarget(
        name: "ShipyardCoreTests",
        dependencies: [
            "ShipyardCommand",
            "ShipyardPings",
            "ShipyardCLISettings",
            "ShipyardNotices",
            "ShipyardConfig",
            "ShipyardControl",
            "ShipyardCore",
            .product(name: "TOMLDecoder", package: "TOMLDecoder"),
        ],
        path: "Tests/ShipyardCoreTests",
        exclude: ["Fixtures"]
    ),
    .testTarget(
        name: "ShipyardControlTests",
        dependencies: ["ShipyardCommand", "ShipyardPings", "ShipyardNotices", "ShipyardControl"],
        path: "Tests/ShipyardControlTests"
    ),
]

// The Mac's dependencies are declared only when the manifest is read on
// macOS, not just conditioned on it: Swift Build, the default build system
// since Swift 6.4, honours the condition for ShipyardConfig itself but still
// links the package products below it into a Linux build (TOMLDecoder, before
// CLISettings brought it in on purpose). The
// conditions stay for the native build system, should a Mac build for Linux.
// Its product is `shipyard-cli`, not `shipyard`, because on a case-insensitive
// disk that would be the app's `Shipyard` executable; `make bundle` puts it in
// the app as `Contents/Helpers/shipyard`.
var cliDependencies: [Target.Dependency] = ["ShipyardCommand", "ShipyardPings", "ShipyardCLISettings", "ShipyardNotices"]
#if os(macOS)
cliDependencies += [
    .target(name: "ShipyardConfig", condition: .when(platforms: [.macOS])),
    .target(name: "ShipyardControl", condition: .when(platforms: [.macOS])),
]
#endif
targets.append(
    .executableTarget(
        name: "ShipyardCLI",
        dependencies: cliDependencies,
        path: "Sources/ShipyardCLI"
    )
)

var products: [Product] = [
    .library(name: "ShipyardCommand", targets: ["ShipyardCommand"]),
    .library(name: "ShipyardPings", targets: ["ShipyardPings"]),
    .library(name: "ShipyardCLISettings", targets: ["ShipyardCLISettings"]),
    .library(name: "ShipyardNotices", targets: ["ShipyardNotices"]),
    .library(name: "ShipyardConfig", targets: ["ShipyardConfig"]),
    .library(name: "ShipyardControl", targets: ["ShipyardControl"]),
    .library(name: "ShipyardCore", targets: ["ShipyardCore"]),
    .executable(name: "shipyard-cli", targets: ["ShipyardCLI"]),
]

#if os(macOS)
targets.append(
    .executableTarget(
        name: "ShipyardApp",
        dependencies: ["ShipyardCommand", "ShipyardPings", "ShipyardNotices", "ShipyardConfig", "ShipyardControl", "ShipyardCore"],
        path: "Sources/ShipyardApp",
        resources: [.copy("Resources/AgentLogos"), .copy("Resources/ServiceLogos")]
    )
)
targets.append(
    .testTarget(
        name: "ShipyardAppTests",
        dependencies: ["ShipyardApp", "ShipyardCommand", "ShipyardCLISettings", "ShipyardNotices", "ShipyardControl", "ShipyardCore"],
        path: "Tests/ShipyardAppTests"
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
