import XCTest
@testable import ShotScribeCore

/// The name is the product, and the repo is public — so the first test here is
/// that the default template spells a name exactly as ShotScribe always has.
final class NameTemplateTests: XCTestCase {

    private let date: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 8; c.day = 11; c.hour = 15; c.minute = 41
        return Calendar.current.date(from: c)!
    }()

    private func name(_ template: NameTemplate, label: String = "AWS Billing Console") -> String? {
        Naming.filename(label: label, capturedAt: date, ext: "png", template: template)
    }

    // MARK: The default changes nothing

    func testTheDefaultTemplateReproducesTodaysName() {
        XCTAssertEqual(name(.default), "2026-08-11 1541 AWS Billing Console.png")
    }

    func testTheDefaultTemplateValidates() {
        XCTAssertNil(Naming.validate(.default))
    }

    // MARK: Styles

    func testDateStyles() {
        XCTAssertEqual(name(NameTemplate(dateStyle: .us)), "08-11-2026 1541 AWS Billing Console.png")
        XCTAssertEqual(name(NameTemplate(dateStyle: .compact)), "20260811 1541 AWS Billing Console.png")
    }

    func testTimeStyles() {
        XCTAssertEqual(name(NameTemplate(timeStyle: .dashed)), "2026-08-11 15-41 AWS Billing Console.png")
        XCTAssertEqual(name(NameTemplate(timeStyle: .twelveHour)), "2026-08-11 3.41 PM AWS Billing Console.png")
    }

    func testTitleStyles() {
        XCTAssertEqual(name(NameTemplate(titleStyle: .kebab)), "2026-08-11 1541 aws-billing-console.png")
        XCTAssertEqual(name(NameTemplate(titleStyle: .snake)), "2026-08-11 1541 aws_billing_console.png")
    }

    func testTheTitleIsCutByWordsAndByLength() {
        XCTAssertEqual(name(NameTemplate(titleWords: 1)), "2026-08-11 1541 AWS.png")
        XCTAssertEqual(name(NameTemplate(maxTitleChars: 3)), "2026-08-11 1541 AWS.png")
    }

    // MARK: Layout

    func testTheLayoutCarriesTheSeparatorsAndTheOrder() {
        XCTAssertEqual(name(NameTemplate(layout: "{date}_{time}_{title}", titleStyle: .kebab)),
                       "2026-08-11_1541_aws-billing-console.png")
        XCTAssertEqual(name(NameTemplate(layout: "{title} — {date}")),
                       "AWS Billing Console — 2026-08-11.png")
    }

    /// "Summary off" is not a setting: it is a layout with no `{title}`.
    func testALayoutWithoutATitleNeedsNoLabel() {
        XCTAssertEqual(name(NameTemplate(layout: "{date} {time}"), label: ""), "2026-08-11 1541.png")
    }

    /// Today's contract, kept: no usable label, and a layout that asks for one,
    /// means the file is left alone.
    func testALayoutWantingATitleWithoutOneRendersNothing() {
        XCTAssertNil(name(.default, label: "   "))
    }

    func testIllegalCharactersInTheLabelAreStripped() {
        XCTAssertEqual(name(.default, label: "AWS/Billing: Console"),
                       "2026-08-11 1541 AWS Billing Console.png")
    }

    // MARK: Validation

    /// The idempotency guard. Without it the watcher renames its own output.
    func testATemplateThatSpellsACaptureNameIsRefused() {
        XCTAssertEqual(Naming.validate(NameTemplate(layout: "Screenshot {date} {time} {title}")),
                       .looksLikeACapture)
    }

    func testUnknownAndMissingTokensAreRefused() {
        XCTAssertEqual(Naming.validate(NameTemplate(layout: "{date} {app}")), .unknownToken("{app}"))
        XCTAssertEqual(Naming.validate(NameTemplate(layout: "shot")), .noTokens)
    }

    func testIllegalCharactersInTheLayoutAreRefused() {
        XCTAssertEqual(Naming.validate(NameTemplate(layout: "{date}/{title}")), .illegalCharacters("/"))
    }

    func testTheSampleIsWhatTheTemplateWouldProduce() {
        XCTAssertEqual(Naming.sampleFilename(.default), "2026-08-11 1541 AWS Billing Console.png")
    }

    // MARK: Storage

    func testCodableRoundTrip() throws {
        let template = NameTemplate(layout: "{date}_{title}", dateStyle: .compact, timeStyle: .dashed,
                                    titleStyle: .snake, titleWords: 2, maxTitleChars: 30)
        let data = try JSONEncoder().encode(template)
        XCTAssertEqual(try JSONDecoder().decode(NameTemplate.self, from: data), template)
    }

    /// A template stored by an older build is missing whatever has been added
    /// since. It has to load, with defaults for the gaps: throwing would reset
    /// somebody's naming silently at the caller's `try?`.
    func testAPartialStoredTemplateKeepsTheDefaultsForWhatIsMissing() throws {
        let json = Data(#"{"layout":"{date} {title}"}"#.utf8)
        let template = try JSONDecoder().decode(NameTemplate.self, from: json)
        XCTAssertEqual(template.layout, "{date} {title}")
        XCTAssertEqual(template.dateStyle, .iso)
        XCTAssertEqual(template.titleWords, 3)
    }

    /// The store is the gate: a template that would not validate is not saved.
    func testTheStoreRefusesATemplateThatWouldNotValidate() {
        withThrowawayDefaults {
            let bad = NameTemplate(layout: "Screenshot {date} {title}")
            XCTAssertEqual(ShotScribeDefaults.setNameTemplate(bad), .looksLikeACapture)
            XCTAssertEqual(ShotScribeDefaults.nameTemplate(), .default, "nothing was written")
        }
    }

    func testAValidTemplateIsStoredAndReadBack() {
        withThrowawayDefaults {
            let template = NameTemplate(layout: "{date}_{title}", titleStyle: .kebab)
            XCTAssertNil(ShotScribeDefaults.setNameTemplate(template))
            XCTAssertEqual(ShotScribeDefaults.nameTemplate(), template)
        }
    }

    /// Never the operator's own domain: a test that saved there would change how
    /// their app names captures.
    private func withThrowawayDefaults(_ body: () -> Void) {
        let domain = "shotscribe.tests.\(UUID().uuidString)"
        ShotScribeDefaults.suiteOverride = UserDefaults(suiteName: domain)
        defer {
            ShotScribeDefaults.suiteOverride = nil
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
        body()
    }

    // MARK: Through the Renamer

    func testTheRenamerSpellsTheNameWithItsTemplate() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("name-template-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let raw = dir.appendingPathComponent("Screenshot 2026-08-11 at 3.41.07 PM.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: raw)

        let renamer = Renamer(titler: KeywordTitler(),
                              template: NameTemplate(layout: "{date}_{title}", titleStyle: .kebab))
        let outcome = try await renamer.rename(fileAt: raw, label: "AWS Billing Console", dryRun: true)
        guard case .wouldRename(_, let to) = outcome else {
            return XCTFail("expected a rename, got \(outcome)")
        }
        XCTAssertTrue(to.lastPathComponent.hasSuffix("_aws-billing-console.png"), to.lastPathComponent)
    }
}
