import Foundation

struct ApplicationCandidate: Equatable, Sendable, Identifiable {
    let name: String
    let url: URL
    let iconCacheKey: String
    let normalizedName: String
    let displayURL: URL

    var id: URL { url }

    init(name: String, url: URL, iconCacheKey: String? = nil, displayURL: URL? = nil) {
        self.name = name
        self.url = url
        self.iconCacheKey = iconCacheKey ?? url.path
        normalizedName = SearchNormalizer.normalize(name)
        self.displayURL = displayURL ?? url
    }
}

struct ApplicationCatalog: ApplicationCataloging {
    let roots: [URL]
    private let includesFinder: Bool
    private let fileManager: FileManager

    init(roots: [URL] = Self.standardRoots, includesFinder: Bool = true, fileManager: FileManager = .default) {
        self.roots = roots
        self.includesFinder = includesFinder
        self.fileManager = fileManager
    }

    func scan() throws -> [ApplicationCandidate] {
        var applications = includesFinder ? [Self.finder] : []
        var seen = Set(applications.map { $0.url.path })
        var visitedRoots: Set<String> = []

        func scanRoot(_ root: URL) {
            guard fileManager.fileExists(atPath: root.path),
                  visitedRoots.insert(root.resolvingSymlinksInPath().path).inserted else { return }
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { return }

            for case let url as URL in enumerator where url.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
                let canonicalURL = url.resolvingSymlinksInPath()
                enumerator.skipDescendants()
                guard seen.insert(canonicalURL.path).inserted else { continue }
                applications.append(ApplicationCandidate(
                    name: displayName(for: canonicalURL), url: canonicalURL,
                    displayURL: Self.displayURL(for: canonicalURL)
                ))
                // Only these bundle directories contain user-facing embedded applications.
                for path in ["Contents/Applications", "Contents/Developer/Applications"] {
                    scanRoot(canonicalURL.appending(path: path))
                }
            }
        }
        roots.forEach(scanRoot)

        return applications.sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
    }

    static func displayURL(
        for url: URL,
        applicationsDirectory: URL = URL(fileURLWithPath: "/Applications", isDirectory: true)
    ) -> URL {
        let alias = applicationsDirectory.appending(path: url.lastPathComponent)
        guard FileManager.default.fileExists(atPath: alias.path),
              alias.resolvingSymlinksInPath().path == url.resolvingSymlinksInPath().path else { return url }
        return alias
    }

    private func displayName(for url: URL) -> String {
        let bundleName = Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleName") as? String
        if let bundleName, !bundleName.isEmpty { return bundleName }
        return url.deletingPathExtension().lastPathComponent
    }

    static let finder = ApplicationCandidate(name: "Finder", url: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))

    static let standardRoots = [
        URL(fileURLWithPath: "/Applications", isDirectory: true),
        URL(fileURLWithPath: "/System/Applications", isDirectory: true),
        URL(fileURLWithPath: "/System/Library/CoreServices/Applications", isDirectory: true),
        URL(fileURLWithPath: "/System/Volumes/Preboot/Cryptexes/App/System/Applications", isDirectory: true),
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications", directoryHint: .isDirectory),
    ]
}
