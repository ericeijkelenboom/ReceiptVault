import Foundation
import StoreKit

@MainActor
class StoreKitManager: ObservableObject {
    @Published var isPremiumUser = false
    @Published var products: [Product] = []

    private let subscriptionProductID = "com.receiptvault.subscription.monthly"
    private let oneTimePurchaseID = "com.receiptvault.unlimited"

    static let shared = StoreKitManager()

    init() {
        Task {
            await fetchProducts()
            await restorePurchases()
        }
    }

    func fetchProducts() async {
        do {
            let allProducts = try await Product.products(for: [subscriptionProductID, oneTimePurchaseID])
            self.products = allProducts.sorted { $0.price < $1.price }
        } catch {
            print("Failed to fetch products: \(error)")
        }
    }

    func purchase(_ product: Product) async {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(_) = verification {
                    self.isPremiumUser = true
                }
            case .pending:
                print("Purchase pending")
            case .userCancelled:
                print("User cancelled")
            @unknown default:
                print("Unknown purchase result")
            }
        } catch {
            print("Purchase failed: \(error)")
        }
    }

    func restorePurchases() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if transaction.productID == subscriptionProductID || transaction.productID == oneTimePurchaseID {
                    self.isPremiumUser = true
                    break
                }
            }
        }
    }
}
