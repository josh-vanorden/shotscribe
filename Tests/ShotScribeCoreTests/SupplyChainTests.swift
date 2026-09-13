import XCTest

/// The supply chain here is the absence of one: every product builds from
/// Apple's SDKs alone, and README and SECURITY.md lean on that ("no telemetry,
/// no update check" is easy to audit when there is no third-party code to
/// audit). So the manifest is pinned the way `NameTemplateTests` pins the
/// default name: a dependency, a prebuilt binary or a build plugin arriving in
/// `Package.swift` is outside code running on every machine that builds this,
/// and it must arrive as a decision that updates this test — never as a quiet
/// edit that a review skims past.
final class SupplyChainTests: XCTestCase {

    /// Tests/ShotScribeCoreTests/SupplyChainTests.swift → the repo root.
    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testTheManifestStaysDependencyFree() throws {
        let manifest = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
        XCTAssertFalse(manifest.contains(".package("),
                       "an external package reached Package.swift — adding one is a deliberate decision that updates this test")
        XCTAssertFalse(manifest.contains(".binaryTarget("),
                       "a prebuilt binary target is unauditable code inside a source-only build")
        XCTAssertFalse(manifest.contains(".plugin(") || manifest.contains("plugins:"),
                       "a build plugin runs at compile time on every machine that builds this")
    }

    func testNoResolvedDependencyGraphExists() {
        // With nothing to resolve, SwiftPM writes no Package.resolved; one at
        // the root means the graph grew a node outside this repo by some route
        // the manifest check above did not spell.
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Package.resolved").path),
                       "Package.resolved exists — the dependency graph is no longer empty")
    }
}
