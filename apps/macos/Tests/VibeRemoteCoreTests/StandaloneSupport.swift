// Command Line Tools do not ship XCTest. These small compatibility assertions
// let the same test cases run with swiftc; Xcode/CI still use real XCTest.
#if VIBE_STANDALONE_TESTS
import Foundation

class XCTestCase {}
enum StandaloneFailure: Error { case assertion }
var standaloneFailures = 0

func XCTFail(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    standaloneFailures += 1
    fputs("FAIL \(file):\(line) \(message)\n", stderr)
}

func XCTAssertEqual<T: Equatable>(_ actual: @autoclosure () throws -> T,
                                  _ expected: @autoclosure () throws -> T,
                                  _ message: String = "", file: StaticString = #filePath,
                                  line: UInt = #line) {
    do {
        let a = try actual(), e = try expected()
        if a != e { XCTFail("\(a) != \(e) \(message)", file: file, line: line) }
    } catch { XCTFail("Unexpected error: \(error)", file: file, line: line) }
}

func XCTAssertTrue(_ value: @autoclosure () -> Bool, _ message: String = "",
                   file: StaticString = #filePath, line: UInt = #line) {
    if !value() { XCTFail(message, file: file, line: line) }
}

func XCTAssertFalse(_ value: @autoclosure () -> Bool, _ message: String = "",
                    file: StaticString = #filePath, line: UInt = #line) {
    if value() { XCTFail(message, file: file, line: line) }
}

func XCTAssertNil<T>(_ value: @autoclosure () -> T?, _ message: String = "",
                     file: StaticString = #filePath, line: UInt = #line) {
    if value() != nil { XCTFail(message, file: file, line: line) }
}

func XCTAssertThrowsError<T>(_ value: @autoclosure () throws -> T, _ message: String = "",
                             file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try value(); XCTFail("Expected error. \(message)", file: file, line: line) }
    catch { /* expected */ }
}

func XCTUnwrap<T>(_ value: @autoclosure () throws -> T?, _ message: String = "",
                  file: StaticString = #filePath, line: UInt = #line) throws -> T {
    if let value = try value() { return value }
    XCTFail("Expected non-nil. \(message)", file: file, line: line)
    throw StandaloneFailure.assertion
}
#endif
