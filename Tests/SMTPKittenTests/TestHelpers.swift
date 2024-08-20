// Import XCTest for URL and Data
import XCTest

struct TestHelpers {
    static func fixtureData(for fixture: String) throws -> Data {
        try Data(contentsOf: fixtureUrl(for: fixture))
    }

    private static func fixtureUrl(for fixture: String) -> URL {
        fixturesDirectory().appendingPathComponent(fixture)
    }

    private static func fixturesDirectory(path: String = #file) -> URL {
        let url = URL(fileURLWithPath: path)
        let testsDir = url.deletingLastPathComponent()
        let res = testsDir.appendingPathComponent("Fixtures")
        return res
    }
}
