import Foundation

/// Full receipt details from Core Data.
struct ReceiptDetail: Identifiable {
    let id: UUID
    let filename: String
    let shopName: String
    let date: Date
    let total: Decimal?
    let currency: String?
    let lineItems: [ReceiptDetailLineItem]
}

struct ReceiptDetailLineItem: Identifiable {
    let name: String
    let quantity: Decimal?
    let unitPrice: Decimal?
    let totalPrice: Decimal?

    var id: String { "\(name)-\(quantity ?? 0)-\(unitPrice ?? 0)-\(totalPrice ?? 0)" }
}
