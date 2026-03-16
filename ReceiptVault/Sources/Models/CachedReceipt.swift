import Foundation

struct CachedReceipt: Codable, Identifiable, Hashable {
    let id: UUID
    let shopName: String
    let date: Date
    let total: Decimal?
    let currency: String?
    let scannedAt: Date
    var lineItems: [LineItem]

    init(id: UUID, shopName: String, date: Date, total: Decimal?,
         currency: String?, scannedAt: Date, lineItems: [LineItem] = []) {
        self.id = id
        self.shopName = shopName
        self.date = date
        self.total = total
        self.currency = currency
        self.scannedAt = scannedAt
        self.lineItems = lineItems
    }

    var deleteConfirmationMessage: String {
        let totalText = if let total = total, let currency = currency {
            (total as NSDecimalNumber as Decimal).formatted(.currency(code: currency))
        } else {
            "No total"
        }
        return "Are you sure you want to delete this receipt from \(shopName) on \(date.formatted(date: .abbreviated, time: .omitted)) for \(totalText)?"
    }
}
