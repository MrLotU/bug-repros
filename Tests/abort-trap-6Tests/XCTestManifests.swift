import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(abort_trap_6Tests.allTests),
    ]
}
#endif
