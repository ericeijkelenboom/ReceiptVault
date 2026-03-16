import Foundation

struct LineItem: Codable, Hashable, Identifiable {
    let id: UUID
    let name: String
    let quantity: Decimal?
    let unitPrice: Decimal?
    let totalPrice: Decimal?

    init(name: String, quantity: Decimal? = nil, unitPrice: Decimal? = nil, totalPrice: Decimal? = nil, id: UUID = UUID()) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.totalPrice = totalPrice
    }
}
