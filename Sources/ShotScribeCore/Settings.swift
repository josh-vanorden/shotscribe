import Foundation

/// Where ShotScribe's settings live, for every door onto the engine. The CLI
/// and the MCP server read the same stored template as the app, so one capture
/// gets the same name whichever door renames it.
public enum ShotScribeDefaults {
    public static let appBundleID = "com.joshvanorden.shotscribe"
    public static let nameTemplateKey = "shotscribe.nameTemplate"
    public static let vocabularyKey = "shotscribe.tagVocabulary"
    public static let taggingKey = "shotscribe.tagging"
    public static let aiProviderKey = "shotscribe.ai"
    public static let tileOrderKey = "shotscribe.tiles.order"
    public static let tilesHiddenKey = "shotscribe.tiles.hidden"
    public static let tileUsesKey = "shotscribe.tiles.uses"
    /// The switch this replaced: "Title with Claude", on by default.
    static let legacyUseClaudeKey = "shotscribe.useClaude"

    /// ShotScribe's own preferences domain, reached by name from anything that
    /// is not ShotScribe.app: a host with its own bundle id would otherwise
    /// start blank, and start renaming in a folder the operator never chose.
    /// Inside the app that domain *is* `.standard`, and Apple warns against
    /// naming your own bundle id as a suite — which the branch avoids.
    public static var suite: UserDefaults { suiteOverride ?? environmentSuite ?? resolvedSuite }

    /// `SHOTSCRIBE_DEFAULTS=<domain>` points every door at another settings
    /// domain for that run — the way `SHOTSCRIBE_INDEX` does for the index — so
    /// a titler or a template can be tried from the CLI without touching the
    /// settings the app is using.
    private static let environmentSuite: UserDefaults? = {
        guard let name = ProcessInfo.processInfo.environment["SHOTSCRIBE_DEFAULTS"], !name.isEmpty,
              name != appBundleID else { return nil }
        return UserDefaults(suiteName: name)
    }()

    /// Tests point this at a throwaway domain. Without it they would write the
    /// operator's own naming settings while checking that saving works.
    public static var suiteOverride: UserDefaults?

    private static let resolvedSuite: UserDefaults = {
        Bundle.main.bundleIdentifier == appBundleID
            ? .standard
            : (UserDefaults(suiteName: appBundleID) ?? .standard)
    }()

    /// The stored template — or the shipped default when nothing is stored, the
    /// stored value will not decode, or it no longer validates. A template that
    /// cannot be honoured must not be the reason a capture goes unrenamed.
    public static func nameTemplate() -> NameTemplate {
        guard let data = suite.data(forKey: nameTemplateKey),
              let stored = try? JSONDecoder().decode(NameTemplate.self, from: data),
              Naming.validate(stored) == nil else { return .default }
        return stored
    }

    /// The tags a capture may be filed under. Stored so the pane can edit it and
    /// every door agrees on the same closed list; the shipped list stands in
    /// when **nothing has been stored** — a first run.
    ///
    /// A list stored *empty* is a different thing from one never stored, and
    /// they used to be the same: emptying the field put the sixteen shipped
    /// words straight back, so removing them one at a time never finished
    /// (Josh, 2026-09-15: "deleting the 15 or so examples is still a ?"). The
    /// reasoning behind that — never leave the operator with no way back — is
    /// right, and is now served by `restoreDefaultVocabulary` instead.
    public static func vocabulary() -> [String] {
        guard let stored = suite.stringArray(forKey: vocabularyKey) else {
            return Tagging.defaultVocabulary
        }
        return Tagging.normalised(stored)
    }

    public static func setVocabulary(_ tags: [String]) {
        suite.set(Tagging.normalised(tags), forKey: vocabularyKey)
    }

    /// The way back: forget what was stored, and the shipped list stands in
    /// again. What "empty" costs is that nothing can be filed — which is what
    /// the tagging switch says in words.
    public static func restoreDefaultVocabulary() {
        suite.removeObject(forKey: vocabularyKey)
    }

    /// Whether a rename files the capture under Finder tags at all. On by
    /// default: filing is the feature. Off is a switch, distinct from an empty
    /// vocabulary, so turning it back on costs nothing.
    public static func taggingEnabled() -> Bool {
        suite.object(forKey: taggingKey) == nil ? true : suite.bool(forKey: taggingKey)
    }

    public static func setTaggingEnabled(_ on: Bool) {
        suite.set(on, forKey: taggingKey)
    }

    /// Saves only a template that validates, and hands back the problem when it
    /// does not. Nothing else in the engine checks, so this is the gate.
    @discardableResult
    public static func setNameTemplate(_ template: NameTemplate) -> TemplateProblem? {
        if let problem = Naming.validate(template) { return problem }
        if let data = try? JSONEncoder().encode(template) {
            suite.set(data, forKey: nameTemplateKey)
        }
        return nil
    }

    /// Who titles a capture. Nothing stored means what 1.5 did: Claude Code if
    /// the old switch was on (or never touched), the offline titler if it was
    /// off — so an upgrade changes nobody's titler.
    public static func aiProvider() -> AIProvider {
        if let data = suite.data(forKey: aiProviderKey),
           let stored = try? JSONDecoder().decode(AIProvider.self, from: data) { return stored }
        if suite.object(forKey: legacyUseClaudeKey) != nil, !suite.bool(forKey: legacyUseClaudeKey) {
            return AIProvider(kind: .offline)
        }
        return .default
    }

    public static func setAIProvider(_ provider: AIProvider) {
        if let data = try? JSONEncoder().encode(provider) { suite.set(data, forKey: aiProviderKey) }
    }

    /// The landing zone's arrangement and its tally. Three plain keys rather
    /// than one blob: a list of names, a list of names, and a dictionary of
    /// counts are all readable in `defaults read`, and a value that will not
    /// decode costs one tile's place rather than the whole row.
    public static func landingZone() -> LandingZone {
        LandingZone(
            order: LandingZone.resolve(order: suite.stringArray(forKey: tileOrderKey) ?? []),
            hidden: Set((suite.stringArray(forKey: tilesHiddenKey) ?? []).compactMap(LandingZone.Tile.init(rawValue:))),
            uses: (suite.dictionary(forKey: tileUsesKey) as? [String: Int] ?? [:])
                .reduce(into: [:]) { out, pair in
                    if let tile = LandingZone.Tile(rawValue: pair.key) { out[tile] = pair.value }
                })
    }

    public static func setLandingZone(_ zone: LandingZone) {
        suite.set(zone.order.map(\.rawValue), forKey: tileOrderKey)
        suite.set(zone.hidden.map(\.rawValue).sorted(), forKey: tilesHiddenKey)
        suite.set(Dictionary(uniqueKeysWithValues: zone.uses.map { ($0.key.rawValue, $0.value) }),
                  forKey: tileUsesKey)
    }
}
