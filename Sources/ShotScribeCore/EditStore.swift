import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Darwin

/// What makes a saved edit editable again: the marks as objects, the frame,
/// and whether the picture they sit on is still the untouched original.
public struct EditDocument: Codable, Equatable, Sendable {
    public var version = 1
    /// Annotations only. A redaction is never kept as an object — it is burned
    /// into the picture beside this document, so it cannot be lifted off.
    public var marks: [Mark]
    public var frame: FrameStyle
    /// True while nothing has ever been redacted, which is what makes
    /// "Revert to original" honest.
    public var baseIsOriginal: Bool
    public var saved: Date
    /// The part of the base that is kept, in base pixels. nil is all of it.
    public var crop: CGRect?
    /// The output size as a fraction of the (cropped) base. 1 is as taken.
    public var scale: CGFloat
    /// The mark of ownership over the picture, if it carries one.
    public var watermark: Watermark?

    public init(marks: [Mark], frame: FrameStyle, baseIsOriginal: Bool, saved: Date = Date(),
                crop: CGRect? = nil, scale: CGFloat = 1, watermark: Watermark? = nil) {
        self.marks = marks; self.frame = frame; self.baseIsOriginal = baseIsOriginal; self.saved = saved
        self.crop = crop; self.scale = scale; self.watermark = watermark
    }

    // Kept edits from before crop and scale existed have neither; before
    // watermarks, none of that either.
    private enum CodingKeys: String, CodingKey { case version, marks, frame, baseIsOriginal, saved, crop, scale, watermark }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        marks = try c.decode([Mark].self, forKey: .marks)
        frame = try c.decode(FrameStyle.self, forKey: .frame)
        baseIsOriginal = try c.decode(Bool.self, forKey: .baseIsOriginal)
        saved = try c.decode(Date.self, forKey: .saved)
        crop = try c.decodeIfPresent(CGRect.self, forKey: .crop)
        scale = try c.decodeIfPresent(CGFloat.self, forKey: .scale) ?? 1
        watermark = try c.decodeIfPresent(Watermark.self, forKey: .watermark)
    }
}

/// **Where ShotScribe keeps the editable side of an edit.**
///
/// A saved edit is a flat picture — that is what every other app needs. So
/// that it can be opened and changed again, ShotScribe keeps, per edited
/// capture, the picture underneath the marks and the marks themselves, under
/// its own Application Support folder: never beside the capture, where the
/// watcher, the index and the operator's Finder would all see it.
///
/// **The link is an ID in an extended attribute on the capture.** A path would
/// break the first time the file was renamed; the attribute survives a rename,
/// and `ImageEditor.save` keeps it because it keeps the file's metadata. A copy
/// sent somewhere without its attributes simply arrives as a flat picture.
///
/// **What is never kept:** anything that was redacted. The picture stored here
/// has every pixelation and black-out already burned in, so the one thing a
/// redaction exists to remove is not sitting in a folder waiting to be found.
public enum EditStore {
    static let attribute = "com.joshvanorden.shotscribe.edit"

    /// Tests point this at a scratch folder, so they never write into the
    /// operator's Application Support.
    public static var rootOverride: URL?

    public static var root: URL {
        if let rootOverride { return rootOverride }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("ShotScribe/Edits", isDirectory: true)
    }

    public static func id(of url: URL) -> UUID? {
        let size = getxattr(url.path, attribute, nil, 0, 0, 0)
        guard size > 0, size < 256 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard getxattr(url.path, attribute, &buffer, size, 0, 0) == size else { return nil }
        return UUID(uuidString: String(decoding: buffer, as: UTF8.self))
    }

    static func setID(_ id: UUID, on url: URL) {
        let bytes = Array(id.uuidString.utf8)
        _ = setxattr(url.path, attribute, bytes, bytes.count, 0, 0)
    }

    private static func folder(for id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    /// Whether this capture was edited here and can be edited again.
    public static func hasEdit(_ url: URL) -> Bool {
        guard let id = id(of: url) else { return false }
        return FileManager.default.fileExists(atPath: folder(for: id).appendingPathComponent("edit.json").path)
    }

    /// The picture under the marks, and the marks.
    public static func load(for url: URL) -> (base: CGImage, document: EditDocument)? {
        guard let id = id(of: url) else { return nil }
        let dir = folder(for: id)
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("edit.json")),
              let doc = try? JSONDecoder().decode(EditDocument.self, from: data),
              let base = ImageEditor.load(dir.appendingPathComponent("base.png")) else { return nil }
        return (base, doc)
    }

    /// Keep the editable side of an edit. Call after the flattened picture has
    /// been written over `url`.
    public static func save(base: CGImage, document: EditDocument, for url: URL) throws {
        let id = id(of: url) ?? UUID()
        let dir = folder(for: id)
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        let png = dir.appendingPathComponent("base.png")
        guard let dest = CGImageDestinationCreateWithURL(png as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(dest, base, nil)
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(document).write(to: dir.appendingPathComponent("edit.json"), options: .atomic)
        for file in ["base.png", "edit.json"] {
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dir.appendingPathComponent(file).path)
        }
        setID(id, on: url)
    }

    /// Forget the editable side — after a revert, or when the capture is
    /// deleted for good.
    public static func remove(for url: URL) {
        guard let id = id(of: url) else { return }
        try? FileManager.default.removeItem(at: folder(for: id))
        _ = removexattr(url.path, attribute, 0)
    }
}

extension EditStore {
    /// **Save an edit.** The finished picture goes over `url`; the editable side
    /// is kept here.
    ///
    /// Redactions are burned into the picture that is kept, and only the
    /// annotations stay as objects — so reopening brings back every arrow, box
    /// and label, and never the thing that was hidden.
    ///
    /// `sourceIsOriginal` is whether `source` is still the untouched capture:
    /// true on a first edit, and on a re-edit whose earlier saves never
    /// redacted anything.
    @discardableResult
    public static func commit(source: CGImage, marks: [Mark], frame: FrameStyle,
                              crop: CGRect? = nil, scale: CGFloat = 1, watermark: Watermark? = nil,
                              sourceIsOriginal: Bool, to url: URL) throws -> EditDocument {
        let redactions = marks.filter { $0.kind.redacts }
        let annotations = marks.filter { !$0.kind.redacts }
        let stamp = watermark.flatMap { $0.isEmpty ? nil : $0 }
        guard let base = redactions.isEmpty ? source : ImageEditor.render(source, marks: redactions),
              let finished = ImageEditor.render(base, marks: annotations, crop: crop, scale: scale,
                                                watermark: stamp, frame: frame)
        else { throw CocoaError(.fileWriteUnknown) }
        try ImageEditor.save(finished, over: url)
        let document = EditDocument(marks: annotations, frame: frame,
                                    baseIsOriginal: sourceIsOriginal && redactions.isEmpty,
                                    crop: crop, scale: scale, watermark: stamp)
        try save(base: base, document: document, for: url)
        return document
    }

    /// Put the untouched capture back and forget the edit. Refused — `false` —
    /// once anything has been redacted, because then there is no untouched
    /// capture to put back, by design.
    @discardableResult
    public static func revert(_ url: URL) throws -> Bool {
        guard let (base, document) = load(for: url), document.baseIsOriginal else { return false }
        try ImageEditor.save(base, over: url)
        remove(for: url)
        return true
    }
}

/// **Pictures the operator brought in to frame captures with** — a brand
/// background, a texture — kept by ShotScribe under its own Application
/// Support, so a frame still renders after the file they chose has moved.
public enum BackgroundImages {
    public static var rootOverride: URL?
    public static var root: URL { rootOverride ?? KeptPictures.support("Backgrounds") }

    /// Copy a picture in. The name it is kept under is returned, and is what a
    /// `FrameStyle.Background.image` refers to.
    @discardableResult
    public static func add(_ url: URL) throws -> String { try KeptPictures.add(url, to: root) }
    public static func url(for name: String) -> URL { root.appendingPathComponent(name) }
    public static func load(_ name: String) -> CGImage? { ImageEditor.load(url(for: name)) }
    /// Every picture kept, newest first.
    public static func names() -> [String] { KeptPictures.names(in: root) }
    public static func remove(_ name: String) { try? FileManager.default.removeItem(at: url(for: name)) }
}

/// One folder of pictures the operator brought in, under ShotScribe's own
/// Application Support — the backgrounds and the watermark logos share this.
enum KeptPictures {
    static func support(_ folder: String) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShotScribe/\(folder)", isDirectory: true)
    }

    /// Copy a picture in under a name that is free; the name is returned.
    static func add(_ url: URL, to root: URL) throws -> String {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension.lowercased()
        let stem = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "/", with: "-")
        var name = "\(stem).\(ext)"
        var n = 2
        while fm.fileExists(atPath: root.appendingPathComponent(name).path) {
            name = "\(stem) \(n).\(ext)"; n += 1
        }
        try fm.copyItem(at: url, to: root.appendingPathComponent(name))
        return name
    }

    /// Every picture kept, newest first.
    static func names(in root: URL) -> [String] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.addedToDirectoryDateKey],
                                                       options: [.skipsHiddenFiles]) else { return [] }
        return items.filter(Capture.isCapture)
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.addedToDirectoryDateKey]))?.addedToDirectoryDate ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.addedToDirectoryDateKey]))?.addedToDirectoryDate ?? .distantPast
                return da > db
            }
            .map(\.lastPathComponent)
    }
}

