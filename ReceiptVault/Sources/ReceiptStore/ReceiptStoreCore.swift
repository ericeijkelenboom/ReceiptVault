import Foundation
import CoreData

// MARK: - Import all model types needed
// These come from the Models module within the app

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

    func update(_ cachedReceipt: CachedReceipt) async throws {
        let context = coreDataStack.viewContext
        guard let uuid = UUID(uuidString: cachedReceipt.driveFileId) else { return }

        let request = Receipt.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)

        if let receipt = try context.fetch(request).first {
            receipt.shopName = cachedReceipt.shopName
            receipt.date = cachedReceipt.date
            receipt.total = cachedReceipt.total as NSDecimalNumber?
            receipt.currency = cachedReceipt.currency

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM"
            receipt.quotaMonth = formatter.string(from: cachedReceipt.date)

            coreDataStack.saveContext()
        }
        _ = try await fetchAllReceipts()
    }

    func grouped(searchText: String) -> [(title: String, receipts: [CachedReceipt])] {
        let filtered = searchText.isEmpty
            ? receipts
            : searchReceipts(query: searchText)

        let grouped = Dictionary(grouping: filtered) { receipt in
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: receipt.date)
        }

        return grouped.sorted { a, b in
            guard let dateA = DateFormatter().date(from: a.key),
                  let dateB = DateFormatter().date(from: b.key) else {
                return false
            }
            return dateA > dateB
        }.map { month, receipts in
            let cached = receipts.map { receipt in
                let lineItems = (receipt.lineItems as? Set<CDLineItem>)?
                    .map { LineItem(name: $0.name, quantity: $0.quantity as Decimal?, unitPrice: $0.unitPrice as Decimal?, totalPrice: $0.totalPrice as Decimal?) }
                    .sorted { $0.name < $1.name } ?? []
                return CachedReceipt(
                    driveFileId: receipt.id.uuidString,
                    shopName: receipt.shopName,
                    date: receipt.date,
                    total: receipt.total as Decimal?,
                    currency: receipt.currency,
                    scannedAt: receipt.createdAt,
                    lineItems: lineItems
                )
            }.sorted { $0.date > $1.date }
            return (title: month, receipts: cached)
        }
    }
}
