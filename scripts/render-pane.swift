// Render the hosted pane off-screen with scratch state — no window on the
// operator's screen, no touch of the real index or defaults — and snapshot it
// after driving the model. Used 2026-09-13 to prove the Send-to tile follows
// the provider (it did; the picker's binding was the fault).
//
//   swift build
//   swiftc -O scripts/render-pane.swift -I .build/debug/Modules \
//     .build/debug/ShotScribeCore.build/*.o .build/debug/ShotScribeUI.build/*.o \
//     -framework AppKit -framework SwiftUI -framework Vision -framework AVFoundation \
//     -framework Security -framework ServiceManagement -o /tmp/render-pane
//   mkdir -p /tmp/pane/shots && ln ~/Pictures/Screenshots/<a few>.png /tmp/pane/shots/
//   /tmp/render-pane /tmp/pane          # writes /tmp/pane/*.png
//   HARNESS_VIEW=list /tmp/render-pane /tmp/pane   # the list view instead of tiles
//   HARNESS_SORT=tag /tmp/render-pane /tmp/pane    # grouped by tag
//
// Hard-link the fixtures (a copy gets today's date and no hero). The pane
// stands down while ShotScribe.app runs, which is fine for a render.
import AppKit
import SwiftUI
import ShotScribeCore
import ShotScribeUI

@MainActor func run() {
let root = CommandLine.arguments[1]
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

let suiteName = "shotscribe-harness-\(Int(Date().timeIntervalSince1970))"
let suite = UserDefaults(suiteName: suiteName)!
suite.set(false, forKey: "shotscribe.watching")
suite.set("\(root)/shots", forKey: "shotscribe.folder")
if let view = ProcessInfo.processInfo.environment["HARNESS_VIEW"] { suite.set(view, forKey: "shotView") }
if let sort = ProcessInfo.processInfo.environment["HARNESS_SORT"] { suite.set(sort, forKey: "shotSort") }
ShotScribeDefaults.suiteOverride = suite
ShotIndex.storeOverride = URL(fileURLWithPath: "\(root)/index.json")
for url in ShotIndex.imageFiles(in: URL(fileURLWithPath: "\(root)/shots")) { ShotIndex.record(url) }

let model = ShotScribeModel()
let host = NSHostingView(rootView: ShotScribeView(model: model, chrome: .hosted))
host.frame = NSRect(x: 0, y: 0, width: 1000, height: 820)
let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
window.contentView = host
window.appearance = NSAppearance(named: .aqua)
window.contentView?.layoutSubtreeIfNeeded()

func spin(_ s: TimeInterval) { RunLoop.main.run(until: Date(timeIntervalSinceNow: s)) }
func snap(_ name: String) {
    host.layoutSubtreeIfNeeded()
    let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
    host.cacheDisplay(in: host.bounds, to: rep)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(root)/\(name).png"))
    print("snap \(name): provider=\(model.aiProvider.kind) assistant=\(model.assistantName)")
}
spin(2.0)
snap("0-initial")
model.setAIProvider(AIProvider(kind: .gemini))
spin(1.5); snap("1-gemini")
model.setAIProvider(AIProvider(kind: .codex))
spin(1.5); snap("2-codex")
model.setAIProvider(AIProvider(kind: .cursor))
spin(1.5); snap("3-cursor")
model.setAIProvider(AIProvider(kind: .ollama))
spin(1.5); snap("4-ollama")
model.setAIProvider(AIProvider(kind: .offline))
spin(1.5); snap("5-offline")
model.setAIProvider(AIProvider(kind: .claude))
spin(1.5); snap("6-claude")
suite.removePersistentDomain(forName: suiteName)
}
MainActor.assumeIsolated { run() }
