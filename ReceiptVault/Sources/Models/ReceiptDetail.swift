import Foundation

/// Full receipt details fetched from Drive manifest (includes line items).
struct ReceiptDetail: Identifiable {
    let driveFileId: String
    let filename: String
    let shopName: String
    let date: Date
    let total: Decimal?
    let currency: String?
    let lineItems: [ReceiptDetailLineItem]

    var id: String { driveFileId }
}

struct ReceiptDetailLineItem: Identifiable {
    let name: String
    let quantity: Decimal?
    let unitPrice: Decimal?
    let totalPrice: Decimal?

    var id: String { "\(name)-\(quantity ?? 0)-\(unitPrice ?? 0)-\(totalPrice ?? 0)" }
}
