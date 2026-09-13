import Foundation

/// Which model this machine is set up to use.
///
/// **Deliberately a second, independent implementation of a shared file.**
/// `~/.config/llm/provider.json` is written by whatever on this machine offers
/// the choice, and read by whatever needs it. ShotScribe is only a reader and
/// imports nothing from the writer — that is the whole point. A shared type
/// would mean a package dependency on whichever app happens to host the picker.
///
/// The path is named after the *subject* rather than after any one app, so
/// anything else here can join in without asking permission. The duplication is
/// roughly forty lines and it buys zero coupling; a good trade.
public struct LLMPreference: Sendable, Equatable {

    public enum Provider: String, Sendable {
        case claude, openai, gemini, apple, local

        /// Whether ShotScribe can actually title with it today. Unknown or
        /// unimplemented providers fall back rather than failing — a wrong
        /// setting should cost you good titles, not the feature.
        public var usableHere: Bool {
            switch self {
            case .claude, .local, .openai, .gemini: return true
            case .apple: return false
            }
        }

        public var title: String {
            switch self {
            case .claude: return "Claude"
            case .openai: return "OpenAI"
            case .gemini: return "Gemini"
            case .apple:  return "Apple Intelligence"
            case .local:  return "a local model"
            }
        }
    }

    public var provider: Provider
    public var endpoint: String?
    public var model: String?
    /// False when no file exists — nobody has chosen, so nothing is overridden.
    public var isSet: Bool

    /// Overrides `fileURL`. **Exists so tests never touch the real file.**
    ///
    /// The same lesson as `ShotIndex.storeOverride`: with no seam, testing this
    /// reader meant writing junk into the operator's actual
    /// `~/.config/llm/provider.json` and deleting it between cases — and that
    /// is a machine-level setting other apps here also read, so corrupting it
    /// is not a local mistake. Data a test can reach is data a test will
    /// eventually corrupt; the fix is a seam, not care.
    public static var fileOverride: URL?

    public static var fileURL: URL {
        fileOverride ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/llm/provider.json")
    }

    /// Read it. Any failure means "not set", never a wrong answer: a corrupt
    /// file must not silently switch which model handles your screenshots.
    public static func load() -> LLMPreference {
        guard let data = try? Data(contentsOf: fileURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = root["provider"] as? String,
              let provider = Provider(rawValue: raw)
        else {
            return LLMPreference(provider: .claude, endpoint: nil, model: nil, isSet: false)
        }
        return LLMPreference(provider: provider,
                             endpoint: root["endpoint"] as? String,
                             model: root["model"] as? String,
                             isSet: true)
    }

    /// What to tell the operator when their choice is not one ShotScribe can
    /// honour. Nil when there is nothing to say.
    public var mismatchNote: String? {
        guard isSet, !provider.usableHere else { return nil }
        return "This machine is set to \(provider.title), which ShotScribe cannot use — "
             + "pick a titler in the AI tab."
    }
}
