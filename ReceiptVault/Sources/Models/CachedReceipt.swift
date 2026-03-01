import Foundation

struct CachedReceipt: Codable, Identifiable {
    let driveFileId: String
    let shopName: String
    let date: Date
    let total: Decimal?
    let currency: String?
    let scannedAt: Date

    var id: String { driveFileId }
}
