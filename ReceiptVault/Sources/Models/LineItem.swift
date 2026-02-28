import Foundation

struct LineItem: Codable {
    let name: String
    let quantity: Decimal?
    let unitPrice: Decimal?
    let totalPrice: Decimal?
}
