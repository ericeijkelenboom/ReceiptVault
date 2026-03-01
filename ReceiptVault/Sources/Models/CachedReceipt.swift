import Foundation

struct CachedReceipt: Codable, Identifiable, Hashable {
    let driveFileId: String
    let shopName: String
    let date: Date
    let total: Decimal?
    let currency: String?
    let scannedAt: Date
    var lineItems: [LineItem]

    var id: String { driveFileId }

    init(driveFileId: String, shopName: String, date: Date, total: Decimal?,
         currency: String?, scannedAt: Date, lineItems: [LineItem] = []) {
        self.driveFileId = driveFileId
        self.shopName = shopName
        self.date = date
        self.total = total
        self.currency = currency
        self.scannedAt = scannedAt
        self.lineItems = lineItems
    }

    // Custom decoder so existing cached JSON without "lineItems" still loads correctly.
    enum CodingKeys: String, CodingKey {
        case driveFileId, shopName, date, total, currency, scannedAt, lineItems
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        driveFileId = try c.decode(String.self,  forKey: .driveFileId)
        shopName    = try c.decode(String.self,  forKey: .shopName)
        date        = try c.decode(Date.self,    forKey: .date)
        total       = try c.decodeIfPresent(Decimal.self, forKey: .total)
        currency    = try c.decodeIfPresent(String.self,  forKey: .currency)
        scannedAt   = try c.decode(Date.self,    forKey: .scannedAt)
        lineItems   = try c.decodeIfPresent([LineItem].self, forKey: .lineItems) ?? []
    }
}
