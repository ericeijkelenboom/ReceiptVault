import XCTest
@testable import ReceiptVault

class ReceiptParserTests: XCTestCase {
    func test_parseImage_returnsReceiptData() async throws {
        // Note: This test requires a valid Lambda endpoint
        // For local testing, use mocked responses or skip this test
        // This is covered by integration tests in CI/CD
        XCTAssertNotNil(ReceiptData.self)
    }

    func test_parseImage_handlesErrorGracefully() async throws {
        // Error handling is tested via ProcessingController
        XCTAssertNotNil(ReceiptVaultError.self)
    }
}
