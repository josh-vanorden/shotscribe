// Fit the artwork in assets/ShotScribe-artwork.png to Apple's icon grid — the
// squircle body at 824 of 1024, centred — and write the 1024 master. The body
// edge is found from the alpha along the middle row (the artwork carries its
// own soft shadow, which is kept). Then scripts/make-iconset.sh builds the
// .iconset and .icns from the master.
//
//   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swiftc -O -o .build/fit-icon scripts/fit-icon.swift
//   .build/fit-icon assets/ShotScribe-artwork.png assets/ShotScribe-icon-1024.png
import AppKit

let src = URL(fileURLWithPath: CommandLine.arguments[1]), out = URL(fileURLWithPath: CommandLine.arguments[2])
let image = NSImage(contentsOf: src)!
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
let w = rep.pixelsWide, h = rep.pixelsHigh

// The body: where the middle row and column become solidly opaque.
func edge(_ pts: [(Int, Int)]) -> Int? { pts.first { rep.colorAt(x: $0.0, y: $0.1)!.alphaComponent > 0.6 }.map { $0.0 == w / 2 ? $0.1 : $0.0 } }
let left = edge((0..<w).map { ($0, h / 2) })!, right = edge((0..<w).reversed().map { ($0, h / 2) })!
let top = edge((0..<h).map { (w / 2, $0) })!, bottom = edge((0..<h).reversed().map { (w / 2, $0) })!
let bodyW = CGFloat(right - left), bodyH = CGFloat(bottom - top)
let bodyCX = CGFloat(left + right) / 2, bodyCY = CGFloat(top + bottom) / 2
print("body \(left)-\(right) × \(top)-\(bottom) → \(Int(bodyW))×\(Int(bodyH)) of \(w)×\(h)")

let canvas = 1024, target: CGFloat = 824
let scale = target / max(bodyW, bodyH)
let master = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: canvas, pixelsHigh: canvas, bitsPerSample: 8, samplesPerPixel: 4,
                              hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: master)
NSGraphicsContext.current?.imageInterpolation = .high
// Flip: bitmap y grows downward in the rep, the drawing context is bottom-up.
let drawW = CGFloat(w) * scale, drawH = CGFloat(h) * scale
let originX = CGFloat(canvas) / 2 - bodyCX * scale
let originY = CGFloat(canvas) / 2 - (CGFloat(h) - bodyCY) * scale
image.draw(in: NSRect(x: originX, y: originY, width: drawW, height: drawH), from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
try! master.representation(using: .png, properties: [:])!.write(to: out)
print("wrote \(out.lastPathComponent): body scaled ×\(String(format: "%.3f", scale)) to \(Int(target)) px, centred")
