// swift-tools-version: 6.0
import PackageDescription

// Modules follow concerns, and each build links only what it uses (ADR 0006):
// ShipyardCommand is the foundation any command needs on any machine,
// ShipyardPings the agent's side of pings, ShipyardNotices the agent's
// side of notices (and their route over the tailnet, which reads
// cli.toml), ShipyardCLISettings reading the command's own cli.toml
// (ADR 0008), ShipyardConfig reading the app's
// config.toml (and filing pings by it), ShipyardControl the client side of
// app control (its AppKit launcher compiled only where AppKit exists),
// ShipyardCore the app's rules. The
// libraries build on Linux, where agents develop them. The ShipyardApp target
// (the `Shipyard` executable) uses Apple-only frameworks, so it only exists on
// macOS: `swift build` and `swift test` on Linux never see it. The app module
// isn't named `Shipyard` because that's the core's orchestrator class.
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
        // A notice's click and buttons are a ping's actions (`PingAction`);
        // another machine's route reads cli.toml.
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
        // Recorded GitHub responses, read from the source tree by `StubHTTP.Answer.fixture`.
        exclude: ["Fixtures"]
    ),
    // App control's client through `ShipyardCLI.run`: parsing, the wire
    // format and exit codes, with a fake transport and launcher.
    .testTarget(
        name: "ShipyardControlTests",
        dependencies: ["ShipyardCommand", "ShipyardPings", "ShipyardNotices", "ShipyardControl"],
        path: "Tests/ShipyardControlTests"
    ),
]

// The `shipyard` command line agents send pings with (ADR 0004). On a machine
// without the app it links Command, Pings, CLISettings and Notices only (ADR
// 0005, 0006, 0008, 0010), so TOMLDecoder through CLISettings and
// FoundationNetworking through Notices' tailnet route; on macOS Config too,
// for the filing that reads config.toml, and Control, for the `app` command
// and `notify`'s route over the socket, and never the core. CI checks both
// builds link nothing else.
//
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
        // The known agents' logos (`make agent-logos`), read by `AgentLogoImage`,
        // and GitHub's and Notion's marks (`make service-logos`), read by `SetupBadge`.
        resources: [.copy("Resources/AgentLogos"), .copy("Resources/ServiceLogos")]
    )
)
// The app's own pure helpers (how the panel builds its text) and the control
// server, tested on macOS.
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
