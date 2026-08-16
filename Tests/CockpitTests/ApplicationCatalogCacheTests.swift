import Foundation
import XCTest
@testable import Cockpit

final class ApplicationCatalogCacheTests: XCTestCase {
    func testServesTheLastRefreshedSnapshotWithoutRescanningTheCatalog() throws {
        let clock = ApplicationCandidate(name: "Clock", url: URL(fileURLWithPath: "/Applications/Clock.app"))
        let source = CountingCatalog(applications: [clock])
        let cache = ApplicationCatalogCache(catalog: source)

        XCTAssertEqual(try cache.scan(), [])
        try cache.refresh()
        XCTAssertEqual(try cache.scan(), [clock])
        XCTAssertEqual(try cache.scan(), [clock])
        XCTAssertEqual(source.scanCount, 1)
    }
}

private final class CountingCatalog: ApplicationCataloging, @unchecked Sendable {
    let applications: [ApplicationCandidate]
    private(set) var scanCount = 0

    init(applications: [ApplicationCandidate]) {
        self.applications = applications
    }

    func scan() throws -> [ApplicationCandidate] {
        scanCount += 1
        return applications
    }
}
