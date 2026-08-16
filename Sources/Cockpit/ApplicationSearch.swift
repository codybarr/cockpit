import Foundation

struct ApplicationSearch {
    enum MatchQuality: Int, Comparable {
        case exact
        case prefix
        case boundary
        case substring
        case fuzzy

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    func ranked<Result: LauncherSearchable>(_ results: [Result], for query: String, usageScore: (Result) -> Int = { _ in 0 }) -> [Result] {
        let tokens = normalizedTokens(in: query)
        guard !tokens.isEmpty else { return [] }

        var matchesByQuality = Array(repeating: [RankedResult<Result>](), count: MatchQuality.fuzzy.rawValue + 1)
        for (index, result) in results.enumerated() {
            guard let quality = matchQuality(for: result.searchLabel, normalizedName: result.normalizedSearchLabel, tokens: tokens) else { continue }
            matchesByQuality[quality.rawValue].append(RankedResult(result: result, usageScore: usageScore(result), originalIndex: index))
        }

        return matchesByQuality.flatMap { matches in
            guard let first = matches.first, matches.contains(where: { $0.usageScore != first.usageScore }) else {
                return matches.map(\.result)
            }
            return matches.sorted {
                $0.usageScore == $1.usageScore ? $0.originalIndex < $1.originalIndex : $0.usageScore > $1.usageScore
            }
            .map(\.result)
        }
    }

    private func matchQuality(for name: String, normalizedName: String, tokens: [String]) -> MatchQuality? {
        let qualities = tokens.compactMap { matchQuality(for: $0, in: normalizedName, originalName: name) }
        guard qualities.count == tokens.count else { return nil }
        return qualities.max()
    }

    private func matchQuality(for token: String, in normalizedName: String, originalName: String) -> MatchQuality? {
        if normalizedName == token { return .exact }
        if normalizedName.hasPrefix(token) { return .prefix }
        if hasWordOrCamelCaseBoundary(token, in: normalizedName, originalName: originalName) { return .boundary }
        if normalizedName.contains(token) { return .substring }
        return isFuzzyMatch(token, in: normalizedName) ? .fuzzy : nil
    }

    private func normalizedTokens(in query: String) -> [String] {
        SearchNormalizer.normalize(query).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private func hasWordOrCamelCaseBoundary(_ token: String, in normalizedName: String, originalName name: String) -> Bool {
        var searchRange = normalizedName.startIndex..<normalizedName.endIndex
        while let range = normalizedName.range(of: token, range: searchRange) {
            let index = range.lowerBound
            let isStart = index == name.startIndex
            let previous = isStart ? nil : name[name.index(before: index)]
            let current = name[index]
            let isWordBoundary = previous.map { !$0.isLetter && !$0.isNumber } ?? false
            let isCamelCaseBoundary = previous.map { $0.isLowercase && current.isUppercase } ?? false
            if isWordBoundary || isCamelCaseBoundary { return true }
            searchRange = range.upperBound..<normalizedName.endIndex
        }
        return false
    }

    private func isFuzzyMatch(_ token: String, in name: String) -> Bool {
        var nameIndex = name.startIndex
        for character in token {
            guard let match = name[nameIndex...].firstIndex(of: character) else { return false }
            nameIndex = name.index(after: match)
        }
        return true
    }

    private struct RankedResult<Result> {
        let result: Result
        let usageScore: Int
        let originalIndex: Int
    }
}
