import XCTest
@testable import Cockpit

final class CalculatorTests: XCTestCase {
    func testEvaluatesExpressionsWithPrecedenceAndParentheses() throws {
        XCTAssertEqual(try Calculator.evaluate("2 + 3 * (4 - 1)"), "11")
    }

    func testEvaluatesDecimalsPercentagesAndCurrencySymbolsWithoutTrailingZeroes() throws {
        XCTAssertEqual(try Calculator.evaluate("$20 * 1.08"), "21.6")
        XCTAssertEqual(try Calculator.evaluate("5%"), "0.05")
        XCTAssertEqual(try Calculator.evaluate("1.50 + 2.25"), "3.75")
    }

    func testRejectsMalformedAndIncompleteExpressions() {
        XCTAssertThrowsError(try Calculator.evaluate("2 +"))
        XCTAssertThrowsError(try Calculator.evaluate("2 + nope"))
        XCTAssertThrowsError(try Calculator.evaluate("4 / 0"))
    }
}
