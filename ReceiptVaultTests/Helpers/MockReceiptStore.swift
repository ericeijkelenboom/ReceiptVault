import Foundation
@testable import ReceiptVault

class MockReceiptStore: ObservableObject {
    @Published var receipts: [CachedReceipt] = []
    @Published var isLoading: Bool = false

    var fetchAllReceiptsThrows: Error?
    var saveReceiptThrows: Error?

    func fetchAllReceipts() async throws -> [CachedReceipt] {
        if let error = fetchAllReceiptsThrows {
            throw error
        }
        return receipts
    }

    func saveReceipt(receiptData: ReceiptData, jpgPath: String) async throws {
        if let error = saveReceiptThrows {
            throw error
        }
        let cached = CachedReceipt(
            id: UUID(),
            shopName: receiptData.shopName,
            date: receiptData.date,
            total: receiptData.total,
            currency: receiptData.currency,
            scannedAt: Date(),
            lineItems: receiptData.lineItems
        )
        receipts.append(cached)
    }

    func deleteReceipt(id: UUID) async throws {
        receipts.removeAll { $0.id == id }
    }

    func searchReceipts(query: String) -> [CachedReceipt] {
        receipts.filter { receipt in
            receipt.shopName.lowercased().contains(query.lowercased())
        }
    }
}
