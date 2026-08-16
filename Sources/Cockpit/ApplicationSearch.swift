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

        let ranked = results.enumerated().compactMap { index, result -> RankedResult<Result>? in
            guard let quality = matchQuality(for: result.searchLabel, tokens: tokens) else { return nil }
            return RankedResult(result: result, quality: quality, usageScore: usageScore(result), originalIndex: index)
        }
        return ranked.sorted { lhs, rhs in
            if lhs.quality != rhs.quality { return lhs.quality < rhs.quality }
            if lhs.usageScore != rhs.usageScore { return lhs.usageScore > rhs.usageScore }
            return lhs.originalIndex < rhs.originalIndex
        }
        .map(\.result)
    }

    private func matchQuality(for name: String, tokens: [String]) -> MatchQuality? {
        let normalizedName = normalize(name)
        let qualities = tokens.compactMap { matchQuality(for: $0, in: normalizedName, originalName: name) }
        guard qualities.count == tokens.count else { return nil }
        return qualities.max()
    }

    private func matchQuality(for token: String, in normalizedName: String, originalName: String) -> MatchQuality? {
        if normalizedName == token { return .exact }
        if normalizedName.hasPrefix(token) { return .prefix }
        if hasWordOrCamelCaseBoundary(token, in: originalName) { return .boundary }
        if normalizedName.contains(token) { return .substring }
        return isFuzzyMatch(token, in: normalizedName) ? .fuzzy : nil
    }

    private func normalizedTokens(in query: String) -> [String] {
        normalize(query).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private func hasWordOrCamelCaseBoundary(_ token: String, in name: String) -> Bool {
        var index = name.startIndex
        while index < name.endIndex {
            let isStart = index == name.startIndex
            let previous = isStart ? nil : name[name.index(before: index)]
            let current = name[index]
            let isWordBoundary = previous.map { !$0.isLetter && !$0.isNumber } ?? false
            let isCamelCaseBoundary = previous.map { $0.isLowercase && current.isUppercase } ?? false

            if (isWordBoundary || isCamelCaseBoundary), normalize(String(name[index...])).hasPrefix(token) {
                return true
            }
            index = name.index(after: index)
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
        let quality: MatchQuality
        let usageScore: Int
        let originalIndex: Int
    }
}
