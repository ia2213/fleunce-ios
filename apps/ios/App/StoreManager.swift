import Foundation
import StoreKit

enum StoreError: Error {
    case failedVerification
    case userCancelled
    case unknown
}

@MainActor
class StoreManager: ObservableObject {
    static let shared = StoreManager()
    
    @Published var products: [Product] = []
    @Published var purchasedProductIDs: Set<String> = []
    
    private let productIDs = ["no.william.fleunce.pro.monthly", "no.william.fleunce.pro.yearly"]
    private var updatesTask: Task<Void, Never>?
    
    init() {
        updatesTask = listenForTransactions()
        Task {
            await loadProducts()
            await updatePurchasedStatus()
        }
    }
    
    deinit {
        updatesTask?.cancel()
    }
    
    func listenForTransactions() -> Task<Void, Never> {
        return Task.detached {
            for await result in Transaction.updates {
                do {
                    let transaction = try self.checkVerified(result)
                    await self.updatePurchasedStatus()
                    await transaction.finish()
                } catch {
                    print("Transaction failed verification")
                }
            }
        }
    }
    
    func loadProducts() async {
        do {
            let loadedProducts = try await Product.products(for: productIDs)
            self.products = loadedProducts.sorted { $0.price < $1.price }
        } catch {
            print("Failed to fetch products: \(error)")
        }
    }
    
    func purchase(_ product: Product) async throws {
        let result = try await product.purchase()
        
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await updatePurchasedStatus()
            await transaction.finish()
        case .userCancelled:
            throw StoreError.userCancelled
        case .pending:
            break
        @unknown default:
            throw StoreError.unknown
        }
    }
    
    func updatePurchasedStatus() async {
        var purchased: Set<String> = []
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                if transaction.productType == .autoRenewable || transaction.productType == .nonConsumable {
                    purchased.insert(transaction.productID)
                }
            } catch {
                print("Failed to verify entitlement: \(error)")
            }
        }
        self.purchasedProductIDs = purchased
    }
    
    func restorePurchases() async throws {
        try await AppStore.sync()
        await updatePurchasedStatus()
    }
    
    var isPro: Bool {
        return !purchasedProductIDs.isEmpty
    }
    
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, _):
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }
}
