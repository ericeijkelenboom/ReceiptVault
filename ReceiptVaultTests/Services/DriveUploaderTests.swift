import XCTest
@testable import ReceiptVault

class DriveUploaderTests: XCTestCase {
    var uploader: DriveUploader!

    override func setUp() async throws {
        try await super.setUp()
        uploader = await DriveUploader(authManager: AuthManager())
    }

    func test_currencySymbolForNil_returnsEmptyString() {
        let result = uploader.currencySymbol(for: nil)
        XCTAssertEqual(result, "")
    }

    func test_currencySymbolForUnknownCode_returnsCodeWithSpace() {
        let result = uploader.currencySymbol(for: "XYZ")
        XCTAssertEqual(result, "XYZ ")
    }

    func test_currencySymbolForUSD_returnsDollarSign() {
        let result = uploader.currencySymbol(for: "USD")
        XCTAssertEqual(result, "$")
    }
}
