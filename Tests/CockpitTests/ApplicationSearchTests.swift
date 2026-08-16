import Foundation
import XCTest
@testable import Cockpit

final class ApplicationSearchTests: XCTestCase {
    private let search = ApplicationSearch()

    func testRanksMatchQualityBandsDeterministically() {
        let exact = application("Mail")
        let prefix = application("Mailbox")
        let boundary = application("Fast Mail")
        let substring = application("Email Client")
        let fuzzy = application("My Application Library")

        XCTAssertEqual(search.ranked([fuzzy, substring, boundary, prefix, exact], for: "mail"), [exact, prefix, boundary, substring, fuzzy])
    }

    func testNormalizesCaseAndDiacriticsAndRequiresEveryToken() {
        let cafeNotes = application("Café Notes")
        let notes = application("Notes")

        XCTAssertEqual(search.ranked([notes, cafeNotes], for: "CAFE notes"), [cafeNotes])
    }

    func testTreatsCamelCaseStartsAsMatchBoundaries() {
        let boundary = application("VisualStudioCode")
        let substring = application("InxstudioCase")

        XCTAssertEqual(search.ranked([substring, boundary], for: "studio"), [boundary, substring])
    }

    func testKeepsSourceOrderForEqualMatches() {
        let first = application("Alpha Tool")
        let second = application("Alpha Notes")

        XCTAssertEqual(search.ranked([first, second], for: "alpha"), [first, second])
    }

    func testUsageOnlyBreaksTiesWithinTheSameMatchQualityBand() {
        let exact = application("Mail")
        let prefix = application("Mailbox")

        XCTAssertEqual(search.ranked([prefix, exact], for: "mail", usageScore: { $0 == prefix ? 100 : 0 }), [exact, prefix])
    }

    private func application(_ name: String) -> ApplicationCandidate {
        ApplicationCandidate(name: name, url: URL(fileURLWithPath: "/Applications/\(name).app"))
    }
}
