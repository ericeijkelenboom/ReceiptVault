import Foundation
import CoreData

@MainActor
class ReceiptStoreCore: ObservableObject {
    @Published var receipts: [Receipt] = []
    @Published var isLoading = false

    let coreDataStack = CoreDataStack.shared

    func fetchAllReceipts() async throws -> [Receipt] {
        isLoading = true
        defer { isLoading = false }

        let context = coreDataStack.viewContext
        let sorted = Receipt.sortedFetchRequest()

        let results = try context.fetch(sorted)
        await MainActor.run {
            self.receipts = results
        }
        return results
    }

    func saveReceipt(data: ReceiptData, jpgPath: String) async throws {
        let context = coreDataStack.viewContext
        let receipt = Receipt(context: context)
        receipt.id = UUID()
        receipt.shopName = data.shopName
        receipt.date = data.date
        receipt.total = data.total as NSDecimalNumber?
        receipt.currency = data.currency
        receipt.rawText = data.rawText
        receipt.jpgPath = jpgPath
        receipt.createdAt = Date()

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        receipt.quotaMonth = formatter.string(from: data.date)

        let lineItems = NSMutableSet()
        for item in data.lineItems {
            let lineItem = CDLineItem(context: context)
            lineItem.id = UUID()
            lineItem.name = item.name
            lineItem.quantity = item.quantity as NSDecimalNumber?
            lineItem.unitPrice = item.unitPrice as NSDecimalNumber?
            lineItem.totalPrice = item.totalPrice as NSDecimalNumber?
            lineItem.receipt = receipt
            lineItems.add(lineItem)
        }
        receipt.lineItems = lineItems

        coreDataStack.saveContext()
        _ = try await fetchAllReceipts()
    }

    func deleteReceipt(id: UUID) async throws {
        let context = coreDataStack.viewContext
        let request = Receipt.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)

        if let receipt = try context.fetch(request).first {
            context.delete(receipt)
            coreDataStack.saveContext()
        }
        _ = try await fetchAllReceipts()
    }

    func searchReceipts(query: String) -> [Receipt] {
        receipts.filter { receipt in
            receipt.shopName.lowercased().contains(query.lowercased()) ||
            receipt.rawText.lowercased().contains(query.lowercased())
        }
    }
}
