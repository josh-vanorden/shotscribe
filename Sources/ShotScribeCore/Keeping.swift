import Foundation

/// What is kept — the fourth question a folder watcher owes its user.
///
/// ShotScribe answers *where* (the folder), *when* (the watch toggle) and *how*
/// (the titler). Until 2026-09-03 it never answered *what is kept*: a rename was
/// a move in place with no way back, a burst of twelve captures of one dialog
/// sat as twelve tiles, and nothing ever aged out. This file is that answer —
/// a policy the user sets, and a plan the user confirms.
///
/// Two rules hold everything here. **Clean-up never deletes**: a flagged shot
/// moves to the Trash or to an archive folder the user named, and both can be
/// walked back. And **a plan is shown before it is applied**: `Cleanup.plan` is
/// pure and cheap, `Cleanup.apply` is the only thing that touches disk, and it
/// takes the plan the user just looked at — never a policy it re-evaluates.
public struct KeepPolicy: Codable, Equatable, Sendable {
    /// Consecutive captures closer than this fold into one session tile.
    /// 0 turns grouping off.
    public var sessionGapMinutes: Int
    /// Flag a later capture whose text matches an earlier one.
    public var flagDuplicates: Bool
    /// Flag captures older than this many days. nil = never.
    public var olderThanDays: Int?
    /// Where a flagged capture goes.
    public var destination: Destination

    /// Where a discarded capture goes — from clean-up and from the bin on
    /// every shot alike. `.delete` is the one the user must choose: nothing
    /// is ever removed outright by default.
    public enum Destination: Codable, Equatable, Sendable {
        case trash
        case archive(path: String)
        case delete

        public var label: String {
            switch self {
            case .trash:              return "Trash"
            case .archive(let path):  return (path as NSString).lastPathComponent
            case .delete:             return "nowhere — deleted for good"
            }
        }
    }

    public init(sessionGapMinutes: Int = 3, flagDuplicates: Bool = true,
                olderThanDays: Int? = nil, destination: Destination = .trash) {
        self.sessionGapMinutes = sessionGapMinutes
        self.flagDuplicates = flagDuplicates
        self.olderThanDays = olderThanDays
        self.destination = destination
    }

    public static let `default` = KeepPolicy()
}

// MARK: - Sessions

/// A burst: consecutive captures close enough in time to be one act — twelve
/// shots of a dialog while it changes, a screen walked page by page.
public struct Session: Identifiable, Equatable, Sendable {
    /// Chronological, oldest first, whatever order the input came in.
    public var shots: [IndexedShot]
    /// The most common title among the shots, date prefix stripped.
    public var title: String

    public var id: String { shots.first?.path ?? "" }
    public var count: Int { shots.count }
    public var isBurst: Bool { shots.count > 1 }
    public var start: Date { shots.first?.captured ?? .distantPast }
    public var end: Date { shots.last?.captured ?? .distantPast }
    /// The shot that best stands for the burst: the last one, which shows the
    /// dialog in its final state rather than its first.
    public var representative: IndexedShot? { shots.last }
}

public enum Sessions {
    /// Fold consecutive captures closer than `gapMinutes` into sessions.
    ///
    /// Sessions come back in the direction the input was sorted: a
    /// newest-first browser gets newest-first sessions, with each session's
    /// own shots oldest-first inside. `gapMinutes <= 0` folds nothing — every
    /// shot is its own session, so a view can render one path either way.
    public static func collapse(_ shots: [IndexedShot], gapMinutes: Int) -> [Session] {
        guard gapMinutes > 0, shots.count > 1 else {
            return shots.map { Session(shots: [$0], title: stem(of: $0.name)) }
        }
        let newestFirst = (shots.first?.captured ?? .distantPast) > (shots.last?.captured ?? .distantPast)
        let ordered = shots.sorted { $0.captured < $1.captured }
        let gap = TimeInterval(gapMinutes * 60)

        var sessions: [[IndexedShot]] = []
        for shot in ordered {
            if let last = sessions.last?.last, shot.captured.timeIntervalSince(last.captured) <= gap {
                sessions[sessions.count - 1].append(shot)
            } else {
                sessions.append([shot])
            }
        }
        let built = sessions.map { Session(shots: $0, title: commonTitle($0)) }
        return newestFirst ? built.reversed() : built
    }

    /// "2026-08-11 1541 AWS Billing Console" → "AWS Billing Console", however
    /// the operator's `NameTemplate` spells the stamp and wherever it sits:
    /// stamp-looking parts come off the front and the back, and what is left is
    /// returned with its own spacing intact. A name with no stamp, and a name
    /// that is nothing but stamp, are both returned as they are.
    public static func stem(of name: String) -> String {
        let parts = stampSeparated(name)
        guard parts.count > 1, parts.contains(where: { !isStampPart($0) }) else { return name }
        var first = 0, last = parts.count - 1
        while first < last, isStampPart(parts[first]) { first += 1 }
        while last > first, isStampPart(parts[last]) { last -= 1 }
        return String(name[parts[first].startIndex..<parts[last].endIndex])
    }

    /// The name's parts, split on the separators a template can put between
    /// tokens, each keeping its place in the original string.
    private static func stampSeparated(_ name: String) -> [Substring] {
        var parts: [Substring] = []
        var start = name.startIndex
        for i in name.indices where name[i] == " " || name[i] == "_" {
            if start < i { parts.append(name[start..<i]) }
            start = name.index(after: i)
        }
        if start < name.endIndex { parts.append(name[start...]) }
        return parts
    }

    /// A date, a clock time or an AM/PM marker — never a word.
    private static func isStampPart(_ part: Substring) -> Bool {
        if part.count <= 2, part.allSatisfy(\.isLetter) {
            let marker = part.lowercased()
            return marker == "am" || marker == "pm"
        }
        return part.contains(where: \.isNumber)
            && part.allSatisfy { $0.isNumber || $0 == "-" || $0 == "." }
    }

    /// The title most of the burst wears; on a tie, the earliest.
    static func commonTitle(_ shots: [IndexedShot]) -> String {
        var counts: [String: Int] = [:]
        var firstSeen: [String: Int] = [:]
        for (i, s) in shots.enumerated() {
            let t = stem(of: s.name)
            counts[t, default: 0] += 1
            if firstSeen[t] == nil { firstSeen[t] = i }
        }
        return counts.max { a, b in
            a.value == b.value ? firstSeen[a.key]! > firstSeen[b.key]! : a.value < b.value
        }?.key ?? (shots.first.map { stem(of: $0.name) } ?? "")
    }
}

// MARK: - Clean-up

public enum Cleanup {
    public struct Move: Identifiable, Equatable, Sendable {
        public var shot: IndexedShot
        public var reason: Reason
        public var id: String { shot.path }

        public enum Reason: Equatable, Sendable {
            case duplicate(of: String)
            case olderThan(days: Int)
        }

        /// One line a person can check the move against.
        public var why: String {
            switch reason {
            case .duplicate(let name):    return "same text as “\(name)”"
            case .olderThan(let days):    return "older than \(days) days"
            }
        }
    }

    public struct Plan: Equatable, Sendable {
        public var moves: [Move]
        public var destination: KeepPolicy.Destination
        public var isEmpty: Bool { moves.isEmpty }
        public var duplicates: Int { moves.filter { if case .duplicate = $0.reason { return true }; return false }.count }
        public var stale: Int { moves.count - duplicates }
    }

    /// Two captures say the same thing when their text, lowercased and
    /// whitespace-collapsed, is identical — and long enough to mean it.
    ///
    /// **Thin text is unknown, not a match.** An empty OCR, or a dozen
    /// characters, is what a photo, a blank window or a failed read produces,
    /// and every such shot would otherwise "duplicate" every other. Below the
    /// floor a shot is never flagged as a duplicate of anything.
    static let duplicateFloor = 40

    static func normalised(_ text: String) -> String {
        text.lowercased().split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    /// What the policy would move, and why. Touches nothing. A shot appears at
    /// most once: a duplicate that is also old is listed as a duplicate.
    public static func plan(_ shots: [IndexedShot], policy: KeepPolicy, now: Date = Date()) -> Plan {
        var moves: [Move] = []
        var flagged: Set<String> = []

        if policy.flagDuplicates {
            var byText: [String: [IndexedShot]] = [:]
            for s in shots {
                let key = normalised(s.text)
                guard key.count >= duplicateFloor else { continue }
                byText[key, default: []].append(s)
            }
            for group in byText.values where group.count > 1 {
                let ordered = group.sorted { $0.captured < $1.captured }
                let kept = ordered[0]
                for later in ordered.dropFirst() where !flagged.contains(later.path) {
                    flagged.insert(later.path)
                    moves.append(Move(shot: later, reason: .duplicate(of: kept.name)))
                }
            }
        }
        if let days = policy.olderThanDays, days > 0 {
            let cutoff = now.addingTimeInterval(-TimeInterval(days) * 86_400)
            for s in shots where s.captured < cutoff && !flagged.contains(s.path) {
                flagged.insert(s.path)
                moves.append(Move(shot: s, reason: .olderThan(days: days)))
            }
        }
        moves.sort { $0.shot.captured > $1.shot.captured }
        return Plan(moves: moves, destination: policy.destination)
    }

    public struct Outcome: Equatable, Sendable {
        public var moved: [String] = []
        /// path → what went wrong
        public var failures: [String: String] = [:]
    }

    /// Carry out a plan: Trash via the system (recoverable from Finder), or a
    /// move into the archive folder with a collision suffix. Moved shots leave
    /// the index; failures stay in it and are reported. Synchronous — call it
    /// off the main thread.
    @discardableResult
    public static func apply(_ plan: Plan, fileManager: FileManager = .default) -> Outcome {
        var out = Outcome()
        for move in plan.moves {
            let url = move.shot.url
            do {
                switch plan.destination {
                case .trash:
                    try fileManager.trashItem(at: url, resultingItemURL: nil)
                case .delete:
                    try fileManager.removeItem(at: url)
                case .archive(let path):
                    let dir = URL(fileURLWithPath: path)
                    try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
                    let name = Naming.uniqueName(url.lastPathComponent) {
                        fileManager.fileExists(atPath: dir.appendingPathComponent($0).path)
                    }
                    try fileManager.moveItem(at: url, to: dir.appendingPathComponent(name))
                }
                out.moved.append(url.path)
            } catch {
                out.failures[url.path] = error.localizedDescription
            }
        }
        if !out.moved.isEmpty { ShotIndex.forget(out.moved) }
        return out
    }
}
