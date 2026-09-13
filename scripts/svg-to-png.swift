import AppKit
import WebKit

// Kept as scripts/svg-to-png.swift: CoreSVG (NSImage) dropped Gemini's gradient and
// Quick Look painted a white background; WebKit does neither.
//   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swiftc -O -o .build/svg-to-png scripts/svg-to-png.swift -framework WebKit
//   .build/svg-to-png assets/brands/gemini.svg /tmp/gemini.png 1024   # writes 2048 px (retina) with alpha
// Rasterise an SVG through WebKit on a transparent page: gradients intact,
// alpha intact. usage: svgweb <in.svg> <out.png> <px>
let args = CommandLine.arguments
let svg = try! String(contentsOfFile: args[1], encoding: .utf8)
let out = URL(fileURLWithPath: args[2])
let px = Int(args[3]) ?? 512

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

@MainActor func run() {
    let config = WKWebViewConfiguration()
    let web = WKWebView(frame: NSRect(x: 0, y: 0, width: px, height: px), configuration: config)
    web.setValue(false, forKey: "drawsBackground")
    let window = NSWindow(contentRect: web.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isOpaque = false
    window.backgroundColor = .clear
    window.contentView = web
    let html = """
    <!doctype html><html><head><style>html,body{margin:0;background:transparent;width:\(px)px;height:\(px)px;overflow:hidden}
    svg{width:\(px)px;height:\(px)px;display:block}</style></head><body>\(svg)</body></html>
    """
    web.loadHTMLString(html, baseURL: nil)
    var done = false
    var snapshot: NSImage?
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
        let cfg = WKSnapshotConfiguration()
        cfg.rect = NSRect(x: 0, y: 0, width: px, height: px)
        web.takeSnapshot(with: cfg) { image, error in
            if let error { print("snapshot error: \(error)") }
            snapshot = image; done = true
        }
    }
    while !done { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05)) }
    guard let image = snapshot, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { print("no image"); exit(1) }
    try! rep.representation(using: .png, properties: [:])!.write(to: out)
    let corner = rep.colorAt(x: 1, y: 1)?.alphaComponent ?? -1
    let centre = rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2)?.alphaComponent ?? -1
    print("wrote \(out.lastPathComponent) \(rep.pixelsWide)px, alpha corner=\(corner) centre=\(centre)")
}
MainActor.assumeIsolated { run() }
