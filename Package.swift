// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "shotscribe",
    platforms: [.macOS(.v13)],
    products: [
        // The reusable core — pure logic, no UI. Shared by the CLI, and (next
        // slices) the MCP server, the menu-bar app, and the widget.
        .library(name: "ShotScribeCore", targets: ["ShotScribeCore"]),
        // The dogfoodable command-line tool.
        .executable(name: "shotscribe", targets: ["shotscribe"]),
        // MCP server (stdio) — lets Claude Code / Cowork call the same engine
        // as tools during a terminal session.
        .executable(name: "shotscribe-mcp", targets: ["shotscribe-mcp"]),
        // The face as a library: one view, `ShotScribeSurface`. Standalone by
        // design — it knows nothing about any host that mounts it (see the
        // Doctrine section of the README).
        .library(name: "ShotScribeUI", targets: ["ShotScribeUI"]),
        // Menu bar app — the always-there local UI (bundle it with
        // scripts/package-app.sh).
        .executable(name: "shotscribe-menubar", targets: ["shotscribe-menubar"]),
    ],
    targets: [
        .target(name: "ShotScribeCore"),
        .executableTarget(
            name: "shotscribe",
            dependencies: ["ShotScribeCore"]
        ),
        .executableTarget(
            name: "shotscribe-mcp",
            dependencies: ["ShotScribeCore"]
        ),
        .target(
            name: "ShotScribeUI",
            dependencies: ["ShotScribeCore"],
            // The app icon, so the same artwork appears in the Dock standalone
            // and in a host's rail when mounted.
            ),
        .executableTarget(
            name: "shotscribe-menubar",
            dependencies: ["ShotScribeUI"]
        ),
        .testTarget(
            name: "ShotScribeCoreTests",
            // ShotScribeUI is here for `Log` alone — the owner-only rule on
            // the log file is pinned by LogHardeningTests.
            dependencies: ["ShotScribeCore", "ShotScribeUI"]
        ),
    ]
)
