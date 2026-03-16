import XCTest
@testable import ReceiptVault

class ReceiptParserIntegrationTests: XCTestCase {
    var parser: ReceiptParser!

    override func setUp() {
        super.setUp()
        parser = ReceiptParser()
    }

    // MARK: - JYSK Receipt Test (172.50 DKK)

    func test_parse_jyskReceipt_extractsCorrectStructure() async throws {
        // Load test image: JYSK receipt with 172.50 DKK total
        guard let image = loadTestImage(named: "receipt-rewe-172.50") else {
            XCTFail("Could not load test receipt image")
            return
        }

        let data = try await parser.parse(image: image)

        // Verify basic structure
        XCTAssertNotNil(data.shopName)
        XCTAssertNotNil(data.date)
        XCTAssertNotNil(data.total)
        XCTAssertNotNil(data.currency)
        XCTAssertFalse(data.lineItems.isEmpty)
        XCTAssertNotNil(data.rawText)

        // Verify shop name was extracted (may vary based on image quality/lighting)
        XCTAssertFalse(data.shopName.isEmpty, "Shop name should be extracted: \(data.shopName)")
        print("📍 Detected shop: \(data.shopName), currency: \(data.currency ?? "unknown")")

        // Verify total is approximately 172.50 DKK (allowing for parsing variance)
        if let total = data.total {
            let totalDouble = Double(truncating: total as NSNumber)
            XCTAssert(
                abs(totalDouble - 172.50) < 2.0,
                "Total should be ~172.50 DKK, got: \(total)"
            )
        } else {
            XCTFail("Total should be extracted from receipt")
        }

        // Verify line items were extracted
        XCTAssert(data.lineItems.count > 0, "Should extract multiple line items from receipt")

        // At least one item should have a price
        let itemsWithPrices = data.lineItems.filter { $0.totalPrice != nil }
        XCTAssert(itemsWithPrices.count > 0, "At least one line item should have a price")
    }

    func test_parse_jyskReceipt_lineItemsAreValid() async throws {
        guard let image = loadTestImage(named: "receipt-rewe-172.50") else {
            XCTFail("Could not load test receipt image")
            return
        }

        do {
            let data = try await parser.parse(image: image)

            // Validate each line item structure
            for item in data.lineItems {
                XCTAssertFalse(item.name.isEmpty, "Item name should not be empty")

                // If item has a price, it should be positive
                if let price = item.totalPrice {
                    let priceDouble = Double(truncating: price as NSNumber)
                    XCTAssertGreaterThan(priceDouble, 0, "Item price should be positive: \(item.name)")
                }

                // If item has quantity, it should be positive
                if let qty = item.quantity {
                    let qtyDouble = Double(truncating: qty as NSNumber)
                    XCTAssertGreaterThan(qtyDouble, 0, "Item quantity should be positive: \(item.name)")
                }
            }
        } catch let error as ReceiptVaultError {
            // Lambda may return parsing errors due to Claude response formatting issues
            // This is a known issue with markdown formatting in Claude responses
            print("⚠️ Note: Lambda returned error (possible Claude response formatting issue): \(error)")
            XCTFail("Lambda error (expected in current implementation): \(error)")
        }
    }

    // MARK: - Error Handling Tests

    func test_parse_invalidImage_returnsError() async throws {
        // Create a UIImage that's not a valid receipt
        guard let invalidImage = UIImage(color: .white, size: CGSize(width: 100, height: 100)) else {
            XCTFail("Could not create test image")
            return
        }

        do {
            _ = try await parser.parse(image: invalidImage)
            XCTFail("Should throw error for blank/invalid image")
        } catch {
            // Expected: error should be thrown for invalid input
            XCTAssertNotNil(error)
        }
    }

    func test_parse_respondsWithExpectedFields() async throws {
        guard let image = loadTestImage(named: "receipt-rewe-172.50") else {
            XCTFail("Could not load test receipt image")
            return
        }

        let data = try await parser.parse(image: image)

        // Verify ReceiptData structure matches API contract
        let mirror = Mirror(reflecting: data)
        let propertyNames = Set(mirror.children.compactMap { $0.label })

        let expectedFields = Set([
            "shopName", "date", "total", "currency", "lineItems", "rawText"
        ])

        let missingFields = expectedFields.subtracting(propertyNames)
        XCTAssertTrue(
            missingFields.isEmpty,
            "Response missing expected fields: \(missingFields)"
        )
    }

    // MARK: - Helper Methods

    /// Load a test receipt image from Fixtures directory
    private func loadTestImage(named filename: String) -> UIImage? {
        let bundle = Bundle(for: type(of: self))

        // Try loading from bundle first (for CI/CD)
        if let url = bundle.url(forResource: filename, withExtension: "jpeg") {
            return UIImage(contentsOfFile: url.path)
        }

        // Fallback: try loading from Fixtures directory in test target
        let fixturesPath = "/Users/eric/code/ReceiptVault/ReceiptVaultTests/Fixtures"
        let imagePath = "\(fixturesPath)/\(filename).jpeg"

        if FileManager.default.fileExists(atPath: imagePath) {
            return UIImage(contentsOfFile: imagePath)
        }

        return nil
    }
}

// MARK: - UIImage Helper for Testing

extension UIImage {
    /// Create a solid color test image
    convenience init?(color: UIColor, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        color.setFill()
        UIRectFill(rect)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        guard let cgImage = image?.cgImage else { return nil }
        self.init(cgImage: cgImage)
    }
}
