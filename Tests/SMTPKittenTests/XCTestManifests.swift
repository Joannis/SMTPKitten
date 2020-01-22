import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(SMTPKittenTests.allTests),
    ]
}
#endif
