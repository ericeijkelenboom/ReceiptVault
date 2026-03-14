import Foundation
@testable import ReceiptVault

enum TestFixtures {
    static let sampleLineItem1 = LineItem(
        name: "Whole Grain Bread",
        quantity: 1,
        unitPrice: 4.99,
        totalPrice: 4.99
    )

    static let sampleLineItem2 = LineItem(
        name: "Organic Milk",
        quantity: 2,
        unitPrice: 3.49,
        totalPrice: 6.98
    )

    static let sampleReceiptData = ReceiptData(
        shopName: "Whole Foods Market",
        date: Date(timeIntervalSince1970: 1_710_432_000), // 2024-03-14
        total: 47.20,
        currency: "USD",
        lineItems: [sampleLineItem1, sampleLineItem2],
        rawText: """
        WHOLE FOODS MARKET
        123 Main St, San Francisco
        Date: 03/14/2024
        Total: $47.20
        """
    )

    static let sampleReceiptDataEuro = ReceiptData(
        shopName: "Rewe",
        date: Date(timeIntervalSince1970: 1_710_518_400), // 2024-03-15
        total: 32.50,
        currency: "EUR",
        lineItems: [
            LineItem(name: "Brot", quantity: 1, unitPrice: 2.50, totalPrice: 2.50),
            LineItem(name: "Milch", quantity: 1, unitPrice: 1.20, totalPrice: 1.20)
        ],
        rawText: "REWE Markt GmbH\n32,50 EUR"
    )

    static let sampleReceiptDataNoDate = ReceiptData(
        shopName: "Unknown Shop",
        date: Date(),
        total: nil,
        currency: nil,
        lineItems: [],
        rawText: "Blurry receipt, no visible date"
    )

    static let sampleCachedReceipt = CachedReceipt(
        driveFileId: "file_123",
        shopName: "Whole Foods Market",
        date: Date(),
        total: 47.20,
        currency: "USD",
        scannedAt: Date(),
        lineItems: [sampleLineItem1, sampleLineItem2]
    )
}
