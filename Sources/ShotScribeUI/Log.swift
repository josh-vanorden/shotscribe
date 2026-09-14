import Foundation

/// Tiny append-only log at ~/Library/Logs/ShotScribe.log — a menu bar app has
/// no console, so this is where "why didn't it rename?" gets answered.
enum Log {
    /// Overrides `url`. **Exists so tests never append to the operator's real
    /// log** — the same seam `ShotIndex.storeOverride` cut, for the same reason.
    static var urlOverride: URL?

    static var url: URL {
        urlOverride ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/ShotScribe.log")
    }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func write(_ message: String) {
        let line = "[\(stamp.string(from: Date()))] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        let fm = FileManager.default
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            fm.createFile(atPath: url.path, contents: data,
                          attributes: [.posixPermissions: 0o600])
        }
        // Every line is a name or an error read off the user's screen, so the
        // log is its owner's alone — the index's rule (`ShotIndex.save`),
        // applied to the other file that carries that text. Running on the
        // append path too tightens a log written before the rule existed.
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
