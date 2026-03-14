import XCTest
@testable import ReceiptVault

class ReceiptVaultErrorTests: XCTestCase {
    func test_parseFailure_hasDescription() {
        let error = ReceiptVaultError.parseFailure("Test error message")
        XCTAssertEqual(error.errorDescription, "Test error message")
    }

    func test_authRequired_hasDescription() {
        let error = ReceiptVaultError.authRequired
        XCTAssertNotNil(error.errorDescription)
        XCTAssert(error.errorDescription!.contains("Authentication"))
    }

    func test_uploadFailure_hasDescription() {
        let error = ReceiptVaultError.uploadFailure("Upload failed")
        XCTAssertEqual(error.errorDescription, "Upload failed")
    }

    func test_pdfGenerationFailed_hasDescription() {
        let error = ReceiptVaultError.pdfGenerationFailed
        XCTAssertNotNil(error.errorDescription)
    }
}
