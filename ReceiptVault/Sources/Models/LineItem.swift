import Foundation

struct LineItem: Codable, Hashable {
    let name: String
    let quantity: Decimal?
    let unitPrice: Decimal?
    let totalPrice: Decimal?
}
