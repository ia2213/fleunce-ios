import SwiftUI

@main struct FleunceApp: App {
    @State private var store: LearningStore?
    @State private var startupError: String?
    init() {
        do { _store = State(initialValue: try LearningStore(inMemory: ProcessInfo.processInfo.arguments.contains("--preview") || AudioVerification.requested)) }
        catch { _startupError = State(initialValue: "Fleunce couldn’t open its learning record. Your existing data has not been replaced.") }
    }
    var body: some Scene {
        WindowGroup {
            if let store { RootView(store: store).preferredColorScheme(.light) }
            else {
                ContentUnavailableView("Let’s try again", systemImage: "externaldrive.badge.exclamationmark", description: Text(startupError ?? "The learning record is unavailable."))
                    .preferredColorScheme(.light)
            }
        }
    }
}
import Foundation
import SwiftUI

@MainActor
class FreeTierLimits: ObservableObject {
    static let shared = FreeTierLimits()
    
    private let maxFreeMessagesPerDay = 15
    private let defaults = UserDefaults.standard
    private let keyDate = "freeTierDate"
    private let keyCount = "freeTierCount"
    
    @Published var messagesToday: Int = 0
    
    init() {
        checkAndResetIfNeeded()
    }
    
    func checkAndResetIfNeeded() {
        let lastDateString = defaults.string(forKey: keyDate)
        let todayString = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
        
        if lastDateString != todayString {
            defaults.set(todayString, forKey: keyDate)
            defaults.set(0, forKey: keyCount)
            messagesToday = 0
        } else {
            messagesToday = defaults.integer(forKey: keyCount)
        }
    }
    
    func incrementMessageCount() {
        checkAndResetIfNeeded()
        messagesToday += 1
        defaults.set(messagesToday, forKey: keyCount)
    }
    
    var canSendFreeMessage: Bool {
        checkAndResetIfNeeded()
        return messagesToday < maxFreeMessagesPerDay
    }
    
    var remainingMessages: Int {
        checkAndResetIfNeeded()
        return max(0, maxFreeMessagesPerDay - messagesToday)
    }
}
import SwiftUI
import StoreKit

struct PaywallView: View {
    @StateObject private var store = StoreManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isPurchasing = false
    @State private var error: String?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 16) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 60))
                            .foregroundStyle(FleunceColor.orange)
                            .padding(.top, 40)
                        
                        Text("Unlock Fleunce Pro")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(FleunceColor.ink)
                            .multilineTextAlignment(.center)
                        
                        Text("Master languages faster with unlimited HD voice conversations and deep corrections.")
                            .font(.body)
                            .foregroundStyle(FleunceColor.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    
                    // Features
                    VStack(alignment: .leading, spacing: 20) {
                        FeatureRow(icon: "waveform", title: "Unlimited HD Voice", subtitle: "Practice speaking with zero time limits")
                        FeatureRow(icon: "text.badge.checkmark", title: "Advanced Corrections", subtitle: "Deep grammar and accent feedback")
                        FeatureRow(icon: "book", title: "Infinite Vocabulary", subtitle: "Save and review unlimited words")
                    }
                    .padding(.horizontal, 32)
                    
                    // Products
                    VStack(spacing: 16) {
                        if store.products.isEmpty {
                            ProgressView()
                                .padding()
                        } else {
                            ForEach(store.products) { product in
                                Button {
                                    Task {
                                        await purchase(product)
                                    }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(product.displayName)
                                                .font(.headline)
                                            if let period = product.subscription?.subscriptionPeriod {
                                                Text(period.unit == .year ? "3 days free, then \(product.displayPrice)/yr" : "\(product.displayPrice)/mo")
                                                    .font(.caption)
                                                    .opacity(0.8)
                                            }
                                        }
                                        Spacer()
                                        if product.subscription?.subscriptionPeriod.unit == .year {
                                            Text("Save 30%")
                                                .font(.caption2.bold())
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(.white.opacity(0.2))
                                                .clipShape(Capsule())
                                        }
                                    }
                                    .padding()
                                    .background(product.subscription?.subscriptionPeriod.unit == .year ? FleunceColor.orange : FleunceColor.secondary.opacity(0.1))
                                    .foregroundStyle(product.subscription?.subscriptionPeriod.unit == .year ? .white : FleunceColor.ink)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                }
                                .buttonStyle(.plain)
                                .disabled(isPurchasing)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    
                    if let error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(FleunceColor.orange)
                    }
                    
                    // Legal & Restore
                    VStack(spacing: 16) {
                        Button("Restore Purchases") {
                            Task {
                                do {
                                    try await store.restorePurchases()
                                    if store.isPro { dismiss() }
                                } catch {
                                    self.error = "Could not restore purchases."
                                }
                            }
                        }
                        .font(.footnote.bold())
                        .foregroundStyle(FleunceColor.secondary)
                        
                        HStack(spacing: 16) {
                            Link("Terms of Use", destination: URL(string: "https://fleunce.com/terms")!)
                            Text("•")
                            Link("Privacy Policy", destination: URL(string: "https://fleunce.com/privacy")!)
                        }
                        .font(.caption2)
                        .foregroundStyle(FleunceColor.secondary.opacity(0.6))
                        
                        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                            Link("Manage Subscription", destination: url)
                                .font(.caption2)
                                .foregroundStyle(FleunceColor.secondary.opacity(0.6))
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
            .background(FleunceColor.cream)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(FleunceColor.secondary)
                    }
                }
            }
        }
    }
    
    private func purchase(_ product: Product) async {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            try await store.purchase(product)
            if store.isPro { dismiss() }
        } catch StoreError.userCancelled {
            // normal
        } catch {
            self.error = "Purchase failed. Please try again."
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(FleunceColor.orange)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(FleunceColor.ink)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(FleunceColor.secondary)
            }
        }
    }
}
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
        return Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self = self else { return }
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
    
    func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, _):
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }
}
