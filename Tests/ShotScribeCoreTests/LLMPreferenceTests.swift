import XCTest
@testable import ShotScribeCore

final class LLMPreferenceTests: XCTestCase {

    /// Every case here writes through `LLMPreference.fileOverride`, never to
    /// `~/.config/llm/provider.json`. An earlier version of this file wrote
    /// junk straight into that path and deleted it between cases, restoring a
    /// backup on the way out — which holds only if the run reaches teardown.
    /// It is a machine-level setting other apps here read too, so the fix is a
    /// seam rather than a more careful backup.
    private var sandbox: URL!

    override func setUpWithError() throws {
        sandbox = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("llm-pref-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        LLMPreference.fileOverride = sandbox.appendingPathComponent("provider.json")
    }

    override func tearDownWithError() throws {
        LLMPreference.fileOverride = nil
        try? FileManager.default.removeItem(at: sandbox)
    }

    private func write(_ json: String) throws {
        try Data(json.utf8).write(to: LLMPreference.fileURL)
    }

    /// The seam itself. If this fails, every other case in this file is
    /// writing to the operator's real settings — so assert it rather than
    /// trusting setUp ran.
    func testTheSeamDivertsAwayFromTheRealFile() throws {
        let real = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/llm/provider.json")
        XCTAssertNotEqual(LLMPreference.fileURL, real)
        XCTAssertTrue(LLMPreference.fileURL.path.hasPrefix(sandbox.path))
    }

    /// The gap this closes: the machine had a provider picker and nothing in
    /// ShotScribe read it.
    func testItReadsWhatThePickerWrites() throws {
        // The exact shape the shared settings file uses. Named after its
        // subject, not after any host — this app reads a machine-level
        // preference and has no idea who else writes it.
        try write(#"{"provider":"local","endpoint":"http://127.0.0.1:11434","model":"llama3"}"#)
        let pref = LLMPreference.load()
        XCTAssertEqual(pref.provider, .local)
        XCTAssertEqual(pref.endpoint, "http://127.0.0.1:11434")
        XCTAssertEqual(pref.model, "llama3")
        XCTAssertTrue(pref.isSet)
        XCTAssertTrue(pref.provider.usableHere)
    }

    func testNoFileMeansNobodyChoseRatherThanAChoice() throws {
        try? FileManager.default.removeItem(at: LLMPreference.fileURL)
        let pref = LLMPreference.load()
        XCTAssertFalse(pref.isSet, "absent must not read as a decision")
        XCTAssertNil(pref.mismatchNote, "nothing to warn about when nothing was chosen")
        XCTAssertTrue(pref.provider.usableHere, "and titling still works")
    }

    /// A corrupt file must not silently switch which model reads your screen.
    func testGarbageFallsBackRatherThanGuessing() throws {
        for junk in ["not json", "{}", #"{"provider":"nonesuch"}"#, ""] {
            try write(junk)
            let pref = LLMPreference.load()
            XCTAssertFalse(pref.isSet, "junk was treated as a setting: \(junk)")
            XCTAssertEqual(pref.provider, .claude)
        }
    }

    /// An unsupported choice degrades and says so, rather than failing. Since
    /// 1.6 only Apple Intelligence is unsupported; Gemini has a CLI preset.
    func testAnUnsupportedProviderIsAnnouncedNotIgnored() throws {
        try write(#"{"provider":"apple"}"#)
        let pref = LLMPreference.load()
        XCTAssertTrue(pref.isSet)
        XCTAssertFalse(pref.provider.usableHere)
        let note = try XCTUnwrap(pref.mismatchNote)
        XCTAssertTrue(note.contains("Apple Intelligence"))
        XCTAssertTrue(note.contains("AI tab"))
        try write(#"{"provider":"gemini"}"#)
        XCTAssertTrue(LLMPreference.load().provider.usableHere, "Gemini CLI is a preset now")
    }

    func testASupportedProviderSaysNothing() throws {
        try write(#"{"provider":"claude"}"#)
        XCTAssertNil(LLMPreference.load().mismatchNote)
    }
}
