import XCTest
@testable import ReceiptVault

class ReceiptStoreCoreTests: XCTestCase {
    var store: ReceiptStoreCore!

    override func setUp() {
        super.setUp()
        // MainActor-isolated initialization needs to happen on main thread
        DispatchQueue.main.sync {
            self.store = ReceiptStoreCore()
        }
    }

    override func tearDown() {
        store = nil
        super.tearDown()
    }

    // MARK: - Save Receipt Tests

    func test_saveReceipt_withValidData_savesSucessfully() async throws {
        let receiptData = createDummyReceipt(
            shopName: "Whole Foods",
            total: 47.50,
            currency: "USD",
            itemCount: 3
        )

        try await store.saveReceipt(data: receiptData, jpgPath: "/tmp/receipt.jpg")

        let receipts = try await store.fetchAllReceipts()
        XCTAssertEqual(receipts.count, 1)
        XCTAssertEqual(receipts[0].shopName, "Whole Foods")
        XCTAssertEqual(receipts[0].total as Decimal?, 47.50)
        XCTAssertEqual(receipts[0].currency, "USD")
    }

    func test_saveReceipt_withMultipleLineItems_savesAllItems() async throws {
        let receiptData = createDummyReceipt(
            shopName: "JYSK",
            total: 172.50,
            currency: "DKK",
            itemCount: 5
        )

        try await store.saveReceipt(data: receiptData, jpgPath: "/tmp/receipt.jpg")

        let receipts = try await store.fetchAllReceipts()
        XCTAssertEqual(receipts.count, 1)

        // Unwrap NSSet as Set<CDLineItem>
        guard let lineItems = receipts[0].lineItems as? Set<CDLineItem> else {
            XCTFail("lineItems should be a Set of CDLineItem")
            return
        }
        XCTAssertEqual(lineItems.count, 5, "Should save all line items")

        // Verify each item has correct properties
        for item in lineItems {
            XCTAssertFalse(item.name.isEmpty, "Item name should not be empty")
            if let price = item.totalPrice {
                XCTAssertGreaterThan(price as Decimal, 0, "Item should have price")
            }
        }
    }

    func test_saveReceipt_relationshipIntegrity_lineItemsLinkedToReceipt() async throws {
        let receiptData = createDummyReceipt(
            shopName: "Target",
            total: 89.99,
            currency: "USD",
            itemCount: 2
        )

        try await store.saveReceipt(data: receiptData, jpgPath: "/tmp/receipt.jpg")

        // Access MainActor-isolated context on main thread
        let context = DispatchQueue.main.sync { store.coreDataStack.viewContext }
        let receiptRequest = Receipt.fetchRequest()
        let receipts = try context.fetch(receiptRequest)

        XCTAssertEqual(receipts.count, 1)
        let receipt = receipts[0]

        // Verify relationships are intact
        guard let lineItems = receipt.lineItems as? Set<CDLineItem> else {
            XCTFail("lineItems should be a Set of CDLineItem")
            return
        }
        XCTAssertEqual(lineItems.count, 2, "Receipt should have 2 related line items")

        // Verify inverse relationship
        for item in lineItems {
            XCTAssertNotNil(item.receipt, "Each line item should reference its receipt")
            XCTAssertEqual(item.receipt?.id, receipt.id, "Line item should reference correct receipt")
        }
    }

    func test_saveReceipt_withNoLineItems_stillSaves() async throws {
        // Create a receipt with no items
        let receiptData = ReceiptData(
            shopName: "Corner Store",
            date: Date(),
            total: 5.00,
            currency: "USD",
            lineItems: [],
            rawText: "Test receipt data"
        )

        try await store.saveReceipt(data: receiptData, jpgPath: "/tmp/receipt.jpg")

        let receipts = try await store.fetchAllReceipts()
        XCTAssertEqual(receipts.count, 1)

        guard let lineItems = receipts[0].lineItems as? Set<CDLineItem> else {
            XCTFail("lineItems should be a Set of CDLineItem")
            return
        }
        XCTAssertEqual(lineItems.count, 0, "Should handle empty line items")
    }

    // MARK: - Fetch Tests

    func test_fetchAllReceipts_returnsReceiptsInReverseChronological() async throws {
        let receipt1 = createDummyReceipt(shopName: "Store1", total: 10, currency: "USD", itemCount: 1)
        let receipt2 = createDummyReceipt(shopName: "Store2", total: 20, currency: "USD", itemCount: 1)
        let receipt3 = createDummyReceipt(shopName: "Store3", total: 30, currency: "USD", itemCount: 1)

        try await store.saveReceipt(data: receipt1, jpgPath: "/tmp/1.jpg")
        try await store.saveReceipt(data: receipt2, jpgPath: "/tmp/2.jpg")
        try await store.saveReceipt(data: receipt3, jpgPath: "/tmp/3.jpg")

        let receipts = try await store.fetchAllReceipts()
        XCTAssertEqual(receipts.count, 3)
        // Should be in reverse chronological order (most recent first)
        XCTAssertEqual(receipts[0].shopName, "Store3")
        XCTAssertEqual(receipts[1].shopName, "Store2")
        XCTAssertEqual(receipts[2].shopName, "Store1")
    }

    // MARK: - Delete Tests

    func test_deleteReceipt_removesReceiptAndLineItems() async throws {
        let receiptData = createDummyReceipt(
            shopName: "Delete Test Store",
            total: 50.00,
            currency: "USD",
            itemCount: 3
        )

        try await store.saveReceipt(data: receiptData, jpgPath: "/tmp/receipt.jpg")
        var receipts = try await store.fetchAllReceipts()
        XCTAssertEqual(receipts.count, 1)
        let receiptId = receipts[0].id

        // Delete the receipt
        try await store.deleteReceipt(id: receiptId)

        // Verify it's gone
        receipts = try await store.fetchAllReceipts()
        XCTAssertEqual(receipts.count, 0, "Receipt should be deleted")

        // Verify cascade delete removed line items
        let context = DispatchQueue.main.sync { store.coreDataStack.viewContext }
        let lineItemRequest = CDLineItem.fetchRequest()
        let lineItems = try context.fetch(lineItemRequest)
        XCTAssertEqual(lineItems.count, 0, "Line items should be cascade deleted")
    }

    // MARK: - Update Tests

    func test_updateReceipt_changesProperties() async throws {
        let originalData = createDummyReceipt(
            shopName: "Original Shop",
            total: 100.00,
            currency: "USD",
            itemCount: 1
        )

        try await store.saveReceipt(data: originalData, jpgPath: "/tmp/receipt.jpg")
        var receipts = try await store.fetchAllReceipts()
        let receiptId = receipts[0].id

        // Update the receipt
        let updated = CachedReceipt(
            id: receiptId,
            shopName: "Updated Shop",
            date: Date(),
            total: 150.00,
            currency: "EUR",
            scannedAt: Date(),
            lineItems: []
        )

        try await store.update(updated)

        receipts = try await store.fetchAllReceipts()
        XCTAssertEqual(receipts.count, 1)
        XCTAssertEqual(receipts[0].shopName, "Updated Shop")
        XCTAssertEqual(receipts[0].total as Decimal?, 150.00)
        XCTAssertEqual(receipts[0].currency, "EUR")
    }

    // MARK: - Data Integrity Tests

    func test_saveReceipt_nullableFieldsCanBeNil() async throws {
        var receiptData = createDummyReceipt(
            shopName: "Minimal Store",
            total: nil,  // Optional
            currency: nil,  // Optional
            itemCount: 0
        )

        try await store.saveReceipt(data: receiptData, jpgPath: "/tmp/receipt.jpg")

        let receipts = try await store.fetchAllReceipts()
        XCTAssertEqual(receipts.count, 1)
        XCTAssertNil(receipts[0].total, "Total should be nil")
        XCTAssertNil(receipts[0].currency, "Currency should be nil")
    }

    func test_saveReceipt_preservesDecimalPrecision() async throws {
        let receiptData = createDummyReceipt(
            shopName: "Precision Test",
            total: 19.99,
            currency: "USD",
            itemCount: 1
        )

        try await store.saveReceipt(data: receiptData, jpgPath: "/tmp/receipt.jpg")

        let receipts = try await store.fetchAllReceipts()
        XCTAssertEqual(receipts[0].total as Decimal?, 19.99)
    }

    // MARK: - Grouping Tests

    func test_grouped_organizesReceiptsByMonth() async throws {
        let calendar = Calendar.current
        let now = Date()
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: now)!

        let receipt1 = ReceiptData(
            shopName: "This Month",
            date: now,
            total: 10,
            currency: "USD",
            lineItems: [(0..<1).map { _ in LineItem(name: "Item 1", quantity: 1, unitPrice: 10, totalPrice: 10) }].flatMap { $0 },
            rawText: "Test receipt"
        )

        let receipt2 = ReceiptData(
            shopName: "Last Month",
            date: lastMonth,
            total: 20,
            currency: "USD",
            lineItems: [(0..<1).map { _ in LineItem(name: "Item 1", quantity: 1, unitPrice: 10, totalPrice: 10) }].flatMap { $0 },
            rawText: "Test receipt"
        )

        try await store.saveReceipt(data: receipt1, jpgPath: "/tmp/1.jpg")
        try await store.saveReceipt(data: receipt2, jpgPath: "/tmp/2.jpg")

        let grouped = DispatchQueue.main.sync { store.grouped(searchText: "") }
        XCTAssertEqual(grouped.count, 2, "Should group into 2 months")
    }

    // MARK: - Helper Methods

    private func createDummyReceipt(
        shopName: String,
        total: Decimal? = nil,
        currency: String? = nil,
        itemCount: Int = 0
    ) -> ReceiptData {
        let lineItems = (0..<itemCount).map { i in
            LineItem(
                name: "Item \(i + 1)",
                quantity: Decimal(1),
                unitPrice: Decimal(10.00),
                totalPrice: Decimal(10.00)
            )
        }

        return ReceiptData(
            shopName: shopName,
            date: Date(),
            total: total,
            currency: currency,
            lineItems: lineItems,
            rawText: "Test receipt data"
        )
    }

    private func createInMemoryCoreDataStack() -> CoreDataStack {
        // This would need to be injected or modified to support in-memory stores
        // For now, we'll use the shared stack which uses file-based storage
        // In a future improvement, we could make CoreDataStack testable
        return CoreDataStack.shared
    }
}

// MARK: - Test Fixtures

extension ReceiptData {
    /// Create a test receipt with realistic data
    static func testReceipt(
        shopName: String = "Test Shop",
        total: Decimal = 50.00,
        currency: String = "USD",
        lineItemCount: Int = 2
    ) -> ReceiptData {
        let items = (0..<lineItemCount).map { i in
            LineItem(
                name: "Test Item \(i + 1)",
                quantity: Decimal(1),
                unitPrice: Decimal(10.00),
                totalPrice: Decimal(10.00)
            )
        }

        return ReceiptData(
            shopName: shopName,
            date: Date(),
            total: total,
            currency: currency,
            lineItems: items,
            rawText: "Raw OCR text"
        )
    }
}
