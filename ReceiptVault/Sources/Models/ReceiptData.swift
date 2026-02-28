import Foundation

struct ReceiptData: Codable {
    let shopName: String
    let date: Date
    let total: Decimal?
    let currency: String?
    let lineItems: [LineItem]
    let rawText: String
}
