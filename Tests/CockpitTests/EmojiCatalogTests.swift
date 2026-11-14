import XCTest
@testable import Cockpit

final class EmojiCatalogTests: XCTestCase {
    private let catalog = EmojiCatalog.bundled

    func testBareEmojiPrefixShowsTheFixedPopularSet() {
        XCTAssertEqual(catalog.matches(for: ":").map(\.shortcode), EmojiCatalog.popularShortcodes)
    }

    func testCompleteShortcodeRanksItsEmojiFirst() {
        XCTAssertEqual(catalog.matches(for: ":joy:").first?.character, "😂")
        XCTAssertEqual(catalog.matches(for: ":+1:").first?.character, "👍")
        XCTAssertEqual(catalog.matches(for: ":JOY").first?.character, "😂")
    }

    func testPartialShortcodeRanksPrefixMatchesBeforeOtherMatches() {
        let shortcodes = catalog.matches(for: ":jo").map(\.shortcode)

        XCTAssertEqual(Array(shortcodes.prefix(2)), ["joy", "joy_cat"])
        XCTAssertTrue(shortcodes.contains("joystick"))
        XCTAssertLessThanOrEqual(shortcodes.count, EmojiCatalog.resultLimit)
    }

    func testEachEmojiAppearsOnceLabelledByItsBestMatchingShortcode() {
        let matches = catalog.matches(for: ":thumbs")

        XCTAssertEqual(matches.first, Emoji(character: "👍", shortcode: "thumbsup", description: "thumbs up"))
        XCTAssertEqual(Set(matches.map(\.character)).count, matches.count)
    }

    func testTagsAndDescriptionsMatchAfterShortcodes() {
        XCTAssertTrue(catalog.matches(for: ":tears").contains { $0.character == "😂" })
        XCTAssertEqual(catalog.matches(for: ":zzzzzz"), [])
    }
}
