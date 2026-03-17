import XCTest
@testable import ReceiptVault

/// Tests the complete end-to-end flow: Parse Image → Save to Core Data → Retrieve & Verify
/// This catches integration issues between the parsing layer and storage layer
class ReceiptCoreDataPipelineTests: XCTestCase {
    var parser: ReceiptParser!
    var store: ReceiptStoreCore!

    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run {
            self.parser = ReceiptParser()
            self.store = ReceiptStoreCore(coreDataStack: CoreDataStack(inMemory: true))
        }
    }

    override func tearDown() async throws {
        parser = nil
        store = nil
        try await super.tearDown()
    }

    // MARK: - Full Pipeline Tests

    func test_parseAndSaveReceipt_endToEndFlow_withRealReceipt() async throws {
        // Load test receipt image
        guard let image = loadTestImage(named: "receipt-rewe-172.50") else {
            XCTFail("Could not load test receipt image")
            return
        }

        // Step 1: Parse the receipt
        let parsedData = try await parser.parse(image: image)
        print("✅ Parsed: \(parsedData.shopName) - \(parsedData.currency ?? "no currency")")

        // Step 2: Save to Core Data
        try await store.saveReceipt(data: parsedData, jpgPath: "/tmp/test.jpg")
        print("✅ Saved to Core Data")

        // Step 3: Retrieve and verify
        let receipts = try await store.fetchAllReceipts()
        XCTAssertEqual(receipts.count, 1, "Should have exactly one receipt")

        let saved = receipts[0]
        XCTAssertEqual(saved.shopName, parsedData.shopName)
        XCTAssertEqual(saved.currency, parsedData.currency)
        XCTAssertEqual(saved.total as Decimal?, parsedData.total)

        guard let lineItems = saved.lineItems as? Set<CDLineItem> else {
            XCTFail("lineItems should be a Set of CDLineItem")
            return
        }
        XCTAssertEqual(lineItems.count, parsedData.lineItems.count)

        print("✅ Verified: \(lineItems.count) items saved correctly")
    }

    func test_parseAndSaveMultipleReceipts_createsIndependentRecords() async throws {
        guard let image = loadTestImage(named: "receipt-rewe-172.50") else {
            XCTFail("Could not load test receipt image")
            return
        }

        // Parse the same receipt image twice (simulating different purchases)
        let data1 = try await parser.parse(image: image)
        let data2 = try await parser.parse(image: image)

        // Save both
        try await store.saveReceipt(data: data1, jpgPath: "/tmp/receipt1.jpg")
        try await store.saveReceipt(data: data2, jpgPath: "/tmp/receipt2.jpg")

        // Verify both exist and are independent
        let receipts = try await store.fetchAllReceipts()
        XCTAssertEqual(receipts.count, 2)
        XCTAssertNotEqual(receipts[0].id, receipts[1].id, "Each receipt should have unique ID")
    }

    func test_parseAndSaveReceipt_lineItemsRelationshipValid() async throws {
        guard let image = loadTestImage(named: "receipt-rewe-172.50") else {
            XCTFail("Could not load test receipt image")
            return
        }

        let parsedData = try await parser.parse(image: image)
        try await store.saveReceipt(data: parsedData, jpgPath: "/tmp/test.jpg")

        // Verify relationships at Core Data level
        let context = DispatchQueue.main.sync { store.coreDataStack.viewContext }
        let request = Receipt.fetchRequest()
        let receipts = try context.fetch(request)

        XCTAssertEqual(receipts.count, 1)
        let receipt = receipts[0]

        guard let lineItems = receipt.lineItems as? Set<CDLineItem> else {
            XCTFail("lineItems should be a Set of CDLineItem")
            return
        }

        XCTAssertEqual(lineItems.count, parsedData.lineItems.count, "All parsed items should be saved")

        // Verify each item has correct inverse relationship
        for item in lineItems {
            XCTAssertNotNil(item.receipt, "Each item should reference its receipt")
            XCTAssertEqual(item.receipt?.id, receipt.id, "Item should reference correct receipt")
            XCTAssertFalse(item.name.isEmpty, "Item name should be populated")
        }
    }

    // MARK: - Data Transformation Tests

    func test_parseAndSave_handlesDecimalConversion() async throws {
        guard let image = loadTestImage(named: "receipt-rewe-172.50") else {
            XCTFail("Could not load test receipt image")
            return
        }

        let parsedData = try await parser.parse(image: image)
        try await store.saveReceipt(data: parsedData, jpgPath: "/tmp/test.jpg")

        let receipts = try await store.fetchAllReceipts()
        let saved = receipts[0]

        // Verify decimal was converted and stored correctly
        if let total = parsedData.total, let savedTotal = saved.total {
            XCTAssertEqual(savedTotal as Decimal, total)
        }
    }

    func test_parseAndSave_preservesRawText() async throws {
        guard let image = loadTestImage(named: "receipt-rewe-172.50") else {
            XCTFail("Could not load test receipt image")
            return
        }

        let parsedData = try await parser.parse(image: image)
        try await store.saveReceipt(data: parsedData, jpgPath: "/tmp/test.jpg")

        let receipts = try await store.fetchAllReceipts()
        let saved = receipts[0]

        XCTAssertEqual(saved.rawText, parsedData.rawText, "Raw OCR text should be preserved")
        XCTAssertFalse(saved.rawText.isEmpty, "Raw text should not be empty")
    }

    // MARK: - Error Handling Tests

    func test_saveReceipt_withNullableFieldsMissing_stillSucceeds() async throws {
        let receiptData = ReceiptData(
            shopName: "Test Shop",
            date: Date(),
            total: nil,
            currency: nil,
            lineItems: [
                LineItem(name: "Item 1", quantity: 1, unitPrice: 10.00, totalPrice: 10.00)
            ],
            rawText: "Raw OCR text"
        )

        try await store.saveReceipt(data: receiptData, jpgPath: "/tmp/test.jpg")

        let receipts = try await store.fetchAllReceipts()
        XCTAssertEqual(receipts.count, 1)
        XCTAssertNil(receipts[0].total, "Missing total should be nil")
        XCTAssertNil(receipts[0].currency, "Missing currency should be nil")
    }

    // MARK: - Data Type Tests

    func test_parseAndSave_allDataTypesCorrect() async throws {
        guard let image = loadTestImage(named: "receipt-rewe-172.50") else {
            XCTFail("Could not load test receipt image")
            return
        }

        let parsedData = try await parser.parse(image: image)
        try await store.saveReceipt(data: parsedData, jpgPath: "/tmp/test.jpg")

        let receipts = try await store.fetchAllReceipts()
        let saved = receipts[0]

        // Verify all properties are present and have correct types
        XCTAssertNotNil(saved.id, "ID should be present")
        XCTAssertFalse(saved.shopName.isEmpty, "shopName should be non-empty")
        XCTAssertNotNil(saved.date, "date should be present")
        XCTAssertNotNil(saved.createdAt, "createdAt should be present")

        // Total and currency are optional, but if present, should be correct types
        if let total = saved.total {
            // Type is correct since it came from Core Data NSDecimalNumber
            XCTAssertGreaterThanOrEqual(total as Decimal, 0)
        }

        // Verify lineItems can be accessed
        guard let lineItems = saved.lineItems as? Set<CDLineItem> else {
            XCTFail("lineItems should be a Set of CDLineItem")
            return
        }

        for item in lineItems {
            XCTAssertFalse(item.name.isEmpty, "item name should be non-empty")
            if let qty = item.quantity {
                XCTAssertGreaterThanOrEqual(qty as Decimal, 0)
            }
        }
    }

    // MARK: - Helper Methods

    private func loadTestImage(named filename: String) -> UIImage? {
        let bundle = Bundle(for: type(of: self))

        // Try loading from bundle first
        if let url = bundle.url(forResource: filename, withExtension: "jpeg") {
            return UIImage(contentsOfFile: url.path)
        }

        // Fallback to fixtures directory
        let fixturesPath = "/Users/eric/code/ReceiptVault/ReceiptVaultTests/Fixtures"
        let imagePath = "\(fixturesPath)/\(filename).jpeg"

        if FileManager.default.fileExists(atPath: imagePath) {
            return UIImage(contentsOfFile: imagePath)
        }

        return nil
    }
}
