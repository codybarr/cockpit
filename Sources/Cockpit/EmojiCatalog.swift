import Foundation

struct Emoji: Equatable, Sendable {
    let character: String
    /// The shortcode this result was matched by, without surrounding colons.
    let shortcode: String
    let description: String
}

/// Cockpit's bundled record of emoji shortcodes (GitHub's gemoji names); searched only behind the emoji prefix.
struct EmojiCatalog: Sendable {
    static let prefix: Character = ":"
    static let resultLimit = 30
    static let popularShortcodes = [
        "joy", "heart", "+1", "pray", "sob", "fire", "tada", "sparkles",
        "eyes", "thinking", "100", "rocket",
    ]

    struct Entry: Decodable, Equatable, Sendable {
        let character: String
        let description: String
        let shortcodes: [String]
        let tags: [String]

        enum CodingKeys: String, CodingKey {
            case character = "e", description = "d", shortcodes = "a", tags = "t"
        }
    }

    static let bundled: EmojiCatalog = {
        guard let url = Bundle.main.url(forResource: "Emoji", withExtension: "json")
                ?? Bundle.module.url(forResource: "Emoji", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else {
            NSLog("Cockpit emoji shortcodes are missing from the app bundle.")
            return EmojiCatalog(entries: [])
        }
        return EmojiCatalog(entries: entries)
    }()

    private let entries: [Entry]

    init(entries: [Entry]) {
        self.entries = entries
    }

    /// Matches a launcher query that begins with the emoji prefix, e.g. `:`, `:jo`, or `:joy:`.
    func matches(for query: String) -> [Emoji] {
        var term = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if term.first == Self.prefix { term.removeFirst() }
        if term.last == Self.prefix { term.removeLast() }
        term = term.replacingOccurrences(of: " ", with: "_")
        guard !term.isEmpty else { return popular }

        var ranked: [(rank: Int, index: Int, emoji: Emoji)] = []
        for (index, entry) in entries.enumerated() {
            guard let (rank, shortcode) = Self.bestMatch(of: term, in: entry) else { continue }
            ranked.append((rank, index, Emoji(character: entry.character, shortcode: shortcode, description: entry.description)))
        }
        ranked.sort { ($0.rank, $0.index) < ($1.rank, $1.index) }
        return ranked.prefix(Self.resultLimit).map(\.emoji)
    }

    private var popular: [Emoji] {
        Self.popularShortcodes.compactMap { shortcode in
            entries.first { $0.shortcodes.contains(shortcode) }
                .map { Emoji(character: $0.character, shortcode: shortcode, description: $0.description) }
        }
    }

    /// Lower ranks are better: exact shortcode, shortcode prefix, word-in-shortcode prefix,
    /// shortcode substring, then tag and description-word prefixes.
    private static func bestMatch(of term: String, in entry: Entry) -> (rank: Int, shortcode: String)? {
        var best: (rank: Int, shortcode: String)?
        for shortcode in entry.shortcodes {
            let rank: Int
            if shortcode == term {
                rank = 0
            } else if shortcode.hasPrefix(term) {
                rank = 1
            } else if shortcode.split(separator: "_").contains(where: { $0.hasPrefix(term) }) {
                rank = 2
            } else if shortcode.contains(term) {
                rank = 3
            } else {
                continue
            }
            if rank < best?.rank ?? .max { best = (rank, shortcode) }
        }
        if let best { return best }
        guard let shortcode = entry.shortcodes.first else { return nil }
        if entry.tags.contains(where: { $0.hasPrefix(term) }) { return (4, shortcode) }
        if entry.description.split(separator: " ").contains(where: { $0.hasPrefix(term) }) { return (5, shortcode) }
        return nil
    }
}
