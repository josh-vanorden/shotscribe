import Foundation

/// Where ShotScribe's settings live, for every door onto the engine. The CLI
/// and the MCP server read the same stored template as the app, so one capture
/// gets the same name whichever door renames it.
public enum ShotScribeDefaults {
    public static let appBundleID = "com.joshvanorden.shotscribe"
    public static let nameTemplateKey = "shotscribe.nameTemplate"

    /// ShotScribe's own preferences domain, reached by name from anything that
    /// is not ShotScribe.app: a host with its own bundle id would otherwise
    /// start blank, and start renaming in a folder the operator never chose.
    /// Inside the app that domain *is* `.standard`, and Apple warns against
    /// naming your own bundle id as a suite — which the branch avoids.
    public static var suite: UserDefaults { suiteOverride ?? resolvedSuite }

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
}
