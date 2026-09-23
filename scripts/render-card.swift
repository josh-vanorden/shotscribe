// Render the capture card off-screen — no window on the operator's screen, no
// touch of the real index or defaults — in light and dark, in its three states
// (naming, named, the generic word), over a busy desktop, plus a row of
// candidate colours for the name on the card's own glass. Used 2026-09-23 to
// choose green over gold for the name.
//
//   swift build
//   swiftc -O scripts/render-card.swift -I .build/debug/Modules //     .build/debug/ShotScribeCore.build/*.o .build/debug/ShotScribeUI.build/*.o //     -framework AppKit -framework SwiftUI -framework Vision -framework AVFoundation //     -framework Security -framework ServiceManagement -o /tmp/render-card
//   mkdir -p /tmp/card/in /tmp/card/out
//   ln ~/Pictures/Screenshots/<busy one>.png /tmp/card/in/desktop.png
//   ln ~/Pictures/Screenshots/<a shot>.png /tmp/card/in/shot.png
//   /tmp/render-card /tmp/card/in /tmp/card/out     # writes card-*.png, swatches-*.png
//
// `.ultraThinMaterial` does not blur in `cacheDisplay`: off-screen, the card is
// glass with nothing behind it, and every colour is read over sharp desktop
// text. The harness paints what the material would — a blurred, tinted patch
// under the card — so the reading is the one a screen gives.
import AppKit
import SwiftUI
import ShotScribeCore
import ShotScribeUI

@MainActor func run() {
    let fixtures = CommandLine.arguments[1], out = CommandLine.arguments[2]
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)

    let suiteName = "shotscribe-card-harness-\(Int(Date().timeIntervalSince1970))"
    let suite = UserDefaults(suiteName: suiteName)!
    suite.removePersistentDomain(forName: suiteName)
    ShotScribeDefaults.suiteOverride = suite
    let scratch = URL(fileURLWithPath: out)
    ShotIndex.storeOverride = scratch.appendingPathComponent("index.json")
    InFlight.storeOverride = scratch.appendingPathComponent("inflight.json")
    suite.set(false, forKey: "shotscribe.watching")
    suite.set(fixtures, forKey: "shotscribe.folder")
    let model = ShotScribeModel()

    let desktop = NSImage(contentsOfFile: fixtures + "/desktop.png")!
    let shot = NSImage(contentsOfFile: fixtures + "/shot.png")!

    func snapshot(_ view: NSView, _ name: String) {
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        try! rep.representation(using: .png, properties: [:])!.write(to: scratch.appendingPathComponent(name))
        print("wrote", name)
    }

    func stage<V: View>(_ content: V, width: CGFloat, height: CGFloat, appearance: NSAppearance.Name, name: String) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        let back = NSImageView(frame: container.bounds)
        back.imageScaling = .scaleAxesIndependently
        back.image = desktop
        container.addSubview(back)
        // What .ultraThinMaterial does on screen and cacheDisplay does not:
        // blur what is behind the card and tint it towards the appearance.
        let cardRect = NSRect(x: (width - 560) / 2, y: (height - 132) / 2, width: 560, height: 132)
        let blurred = NSImage(size: container.bounds.size, flipped: false) { rect in
            let ci = CIImage(data: desktop.tiffRepresentation!)!
                .transformed(by: CGAffineTransform(scaleX: rect.width / desktop.size.width, y: rect.height / desktop.size.height))
            let blur = CIFilter(name: "CIGaussianBlur", parameters: [kCIInputImageKey: ci, kCIInputRadiusKey: 22])!.outputImage!
            let out = NSCIImageRep(ciImage: blur.cropped(to: CGRect(origin: .zero, size: rect.size)))
            let img = NSImage(size: rect.size); img.addRepresentation(out)
            NSBezierPath(roundedRect: cardRect, xRadius: 16, yRadius: 16).addClip()
            img.draw(in: rect)
            (appearance == .aqua ? NSColor.white.withAlphaComponent(0.62) : NSColor.black.withAlphaComponent(0.58)).setFill()
            cardRect.fill()
            return true
        }
        let glass = NSImageView(frame: container.bounds)
        glass.image = blurred
        container.addSubview(glass)
        let host = NSHostingView(rootView: content)
        host.frame = NSRect(x: (width - 560) / 2, y: (height - 132) / 2, width: 560, height: 132)
        container.addSubview(host)
        window.contentView = container
        snapshot(container, name)
    }

    for appearance: NSAppearance.Name in [.aqua, .darkAqua] {
        let tag = appearance == .aqua ? "light" : "dark"
        for (label, to, generic) in [("naming", nil as String?, false),
                                     ("named", "2026-09-22 0930 Company Org Chart.png", false),
                                     ("generic", "2026-09-22 0930 Screenshot (2).png", true)] {
            let state = CaptureCardState(url: URL(fileURLWithPath: fixtures + "/shot.png"),
                                         from: "Screenshot 2026-09-22 at 9.30.16 AM.png", to: to)
            state.generic = generic
            state.image = shot
            let card = CaptureCard(state: state, model: model, open: {}, dismiss: {}, hovering: { _ in })
            stage(card, width: 760, height: 220, appearance: appearance, name: "card-\(tag)-\(label).png")
        }
        // Candidates for the name, on the card's own glass.
        let swatches = VStack(alignment: .leading, spacing: 6) {
            ForEach(Array([
                ("green  (the palette)", ShotPalette.named),
                ("systemGreen", Color(nsColor: .systemGreen)),
                ("gold  #9A6700 / #E3B341", Color(nsColor: NSColor(name: nil) { a in
                    a.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                        ? NSColor(srgbRed: 0.89, green: 0.70, blue: 0.25, alpha: 1)
                        : NSColor(srgbRed: 0.60, green: 0.40, blue: 0.00, alpha: 1) })),
                ("systemOrange", Color(nsColor: .systemOrange)),
                ("secondary  (generic)", Color.secondary),
            ].enumerated()), id: \.offset) { pair in
                HStack {
                    Text("2026-09-22 0930 Company Org Chart").font(.callout.weight(.semibold)).foregroundStyle(pair.element.1)
                    Spacer()
                    Text(pair.element.0).font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(14)
        .frame(width: 560, height: 132)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial))
        stage(swatches, width: 760, height: 220, appearance: appearance, name: "swatches-\(tag).png")
    }
}
MainActor.assumeIsolated { run() }
