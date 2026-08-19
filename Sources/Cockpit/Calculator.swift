import Foundation

struct Calculation: Equatable, Sendable {
    let value: String
}

enum Calculator {
    static func evaluate(_ expression: String) throws -> String {
        try calculate(expression).value
    }

    static func calculate(_ expression: String) throws -> Calculation {
        var parser = Parser(expression)
        let value = try parser.parse()
        return Calculation(value: NSDecimalNumber(decimal: value).stringValue)
    }

    private struct Parser {
        private let characters: [Character]
        private var index = 0

        init(_ expression: String) {
            characters = expression.filter { character in
                !character.unicodeScalars.allSatisfy { $0.properties.generalCategory == .currencySymbol }
            }
        }

        mutating func parse() throws -> Decimal {
            let value = try parseSum()
            skipWhitespace()
            guard index == characters.endIndex else { throw CalculatorError.invalidExpression }
            return value
        }

        private mutating func parseSum() throws -> Decimal {
            var value = try parseProduct()
            while true {
                skipWhitespace()
                if consume("+") {
                    value += try parseProduct()
                } else if consume("-") {
                    value -= try parseProduct()
                } else {
                    return value
                }
            }
        }

        private mutating func parseProduct() throws -> Decimal {
            var value = try parsePercent()
            while true {
                skipWhitespace()
                if consume("*") {
                    value *= try parsePercent()
                } else if consume("/") {
                    let divisor = try parsePercent()
                    guard divisor != 0 else { throw CalculatorError.divisionByZero }
                    value /= divisor
                } else {
                    return value
                }
            }
        }

        private mutating func parsePercent() throws -> Decimal {
            var value = try parsePrimary()
            while true {
                skipWhitespace()
                guard consume("%") else { return value }
                value /= 100
            }
        }

        private mutating func parsePrimary() throws -> Decimal {
            skipWhitespace()
            if consume("+") { return try parsePrimary() }
            if consume("-") { return -(try parsePrimary()) }
            if consume("(") {
                let value = try parseSum()
                skipWhitespace()
                guard consume(")") else { throw CalculatorError.invalidExpression }
                return value
            }
            return try parseNumber()
        }

        private mutating func parseNumber() throws -> Decimal {
            skipWhitespace()
            let start = index
            var hasDecimalPoint = false
            var digitCount = 0

            while index < characters.endIndex {
                let character = characters[index]
                if character.isWholeNumber {
                    digitCount += 1
                    index += 1
                } else if character == ".", !hasDecimalPoint {
                    hasDecimalPoint = true
                    index += 1
                } else {
                    break
                }
            }

            guard digitCount > 0,
                  let value = Decimal(string: String(characters[start..<index]), locale: Locale(identifier: "en_US_POSIX")) else {
                throw CalculatorError.invalidExpression
            }
            return value
        }

        private mutating func skipWhitespace() {
            while index < characters.endIndex, characters[index].isWhitespace {
                index += 1
            }
        }

        private mutating func consume(_ expected: Character) -> Bool {
            guard index < characters.endIndex, characters[index] == expected else { return false }
            index += 1
            return true
        }
    }

    private enum CalculatorError: Error {
        case invalidExpression
        case divisionByZero
    }
}
