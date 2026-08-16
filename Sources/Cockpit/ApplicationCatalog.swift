import Foundation

struct ApplicationCandidate: Equatable, Sendable, Identifiable {
    let name: String
    let url: URL
    let iconCacheKey: String

    var id: URL { url }

    init(name: String, url: URL, iconCacheKey: String? = nil) {
        self.name = name
        self.url = url
        self.iconCacheKey = iconCacheKey ?? url.path
    }
}

struct ApplicationCatalog: ApplicationCataloging {
    let roots: [URL]
    private let fileManager: FileManager

    init(roots: [URL] = Self.standardRoots, fileManager: FileManager = .default) {
        self.roots = roots
        self.fileManager = fileManager
    }

    func scan() throws -> [ApplicationCandidate] {
        var applications: [ApplicationCandidate] = []

        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator where url.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
                let canonicalURL = url.resolvingSymlinksInPath()
                applications.append(ApplicationCandidate(name: displayName(for: canonicalURL), url: canonicalURL))
                enumerator.skipDescendants()
            }
        }

        return applications.sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
    }

    private func displayName(for url: URL) -> String {
        let bundleName = Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleName") as? String
        if let bundleName, !bundleName.isEmpty { return bundleName }
        return url.deletingPathExtension().lastPathComponent
    }

    static let standardRoots = [
        URL(fileURLWithPath: "/Applications", isDirectory: true),
        URL(fileURLWithPath: "/System/Applications", isDirectory: true),
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications", directoryHint: .isDirectory),
    ]
}
