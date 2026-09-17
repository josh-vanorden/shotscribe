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

    public static var root: URL { rootOverride ?? KeptPictures.support("Edits") }

    public static func id(of url: URL) -> UUID? {
        Xattr.read(attribute, at: url.path, limit: 255).flatMap { UUID(uuidString: String(decoding: $0, as: UTF8.self)) }
    }

    static func setID(_ id: UUID, on url: URL) {
        Xattr.write(Data(id.uuidString.utf8), attribute, at: url.path)
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
        try ImageEditor.writePNG(base, to: dir.appendingPathComponent("base.png"))
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
        Xattr.remove(attribute, at: url.path)
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
        var stamp = watermark.flatMap { $0.isEmpty ? nil : $0 }
        if let s = stamp?.stamp {
            // The file carries the moment it was saved and the digest of what
            // this edit started from; the capture time is the file's own.
            let captured = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate
            stamp?.stamp = s.filled(source: source, capturedAt: captured, sourceIsOriginal: sourceIsOriginal)
        }
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

/// **Pictures the operator brought in** — frame backgrounds, watermark logos —
/// kept by ShotScribe under its own Application Support, so a frame or a
/// watermark still renders after the file they chose has moved. One store per
/// folder; `BackgroundImages` and `WatermarkImages` are the two.
///
/// `load` remembers the last picture decoded, since the canvas asks for it on
/// every paint and the save asks once more on another thread.
public final class KeptPictures: @unchecked Sendable {
    public let folder: String
    /// Tests point this at a scratch folder.
    public var rootOverride: URL?
    private let lock = NSLock()
    private var last: (name: String, image: CGImage)?

    public init(folder: String) { self.folder = folder }

    public var root: URL { rootOverride ?? Self.support(folder) }

    static func support(_ folder: String) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShotScribe/\(folder)", isDirectory: true)
    }

    /// Copy a picture in under a name that is free; the name is returned, and
    /// is what a frame or a watermark refers to.
    @discardableResult
    public func add(_ url: URL) throws -> String {
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

    public func url(for name: String) -> URL { root.appendingPathComponent(name) }

    public func load(_ name: String) -> CGImage? {
        lock.lock(); defer { lock.unlock() }
        if let last, last.name == name { return last.image }
        guard let image = ImageEditor.load(url(for: name)) else { return nil }
        last = (name, image)
        return image
    }

    /// Every picture kept, newest first.
    public func names() -> [String] {
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

    public func remove(_ name: String) {
        try? FileManager.default.removeItem(at: url(for: name))
        lock.lock(); defer { lock.unlock() }
        if last?.name == name { last = nil }
    }

    /// Let go of the decoded picture — when no window shows it any more.
    public func forget() {
        lock.lock(); defer { lock.unlock() }
        last = nil
    }
}

/// Pictures behind a framed capture.
public let BackgroundImages = KeptPictures(folder: "Backgrounds")
/// Logos to watermark with.
public let WatermarkImages = KeptPictures(folder: "Watermarks")
