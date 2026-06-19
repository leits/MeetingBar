//
//  PatronageService.swift
//  MeetingBar
//

import Combine
import Foundation
import StoreKit

enum PatronageProducts {
    static let threeMonth = "leits.MeetingBar.patronage.3Month"
    static let sixMonth = "leits.MeetingBar.patronage.6Month"
    static let twelveMonth = "leits.MeetingBar.patronage.12Month"

    static let all = [threeMonth, sixMonth, twelveMonth]

    static func duration(for productID: String) -> Int? {
        switch productID {
        case threeMonth: 3
        case sixMonth: 6
        case twelveMonth: 12
        default: nil
        }
    }
}

struct PatronageTransaction: Equatable, Sendable {
    let id: UInt64
    let productID: String
    let quantity: Int
}

enum PatronagePurchaseResult: Equatable, Sendable {
    case purchased(PatronageTransaction)
    case pending
    case cancelled
}

enum PatronageStoreError: LocalizedError {
    case productUnavailable
    case failedVerification

    var errorDescription: String? {
        switch self {
        case .productUnavailable:
            "The selected patronage product is unavailable."
        case .failedVerification:
            "The App Store transaction could not be verified."
        }
    }
}

@MainActor
protocol PatronageStore: AnyObject {
    func loadProducts(identifiers: [String]) async throws -> Set<String>
    func purchase(productID: String) async throws -> PatronagePurchaseResult
    func currentEntitlements() async -> [PatronageTransaction]
    func transactionUpdates() -> AsyncStream<PatronageTransaction>
    func finish(transactionID: UInt64) async
    func sync() async throws
}

@MainActor
final class StoreKitPatronageStore: PatronageStore {
    private var productsByID: [String: Product] = [:]
    private var transactionsByID: [UInt64: StoreKit.Transaction] = [:]

    func loadProducts(identifiers: [String]) async throws -> Set<String> {
        let products = try await Product.products(for: identifiers)
        productsByID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
        return Set(productsByID.keys)
    }

    func purchase(productID: String) async throws -> PatronagePurchaseResult {
        if productsByID[productID] == nil {
            _ = try await loadProducts(identifiers: PatronageProducts.all)
        }
        guard let product = productsByID[productID] else {
            throw PatronageStoreError.productUnavailable
        }

        switch try await product.purchase() {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                throw PatronageStoreError.failedVerification
            }
            transactionsByID[transaction.id] = transaction
            return .purchased(makeTransaction(from: transaction))
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            throw PatronageStoreError.failedVerification
        }
    }

    func currentEntitlements() async -> [PatronageTransaction] {
        var entitlements: [PatronageTransaction] = []

        for await verification in StoreKit.Transaction.currentEntitlements {
            appendVerified(verification, to: &entitlements)
        }

        return entitlements
    }

    func transactionUpdates() -> AsyncStream<PatronageTransaction> {
        AsyncStream { continuation in
            let task = Task { @MainActor [weak self] in
                for await verification in StoreKit.Transaction.updates {
                    guard !Task.isCancelled else { break }
                    guard case .verified(let transaction) = verification else { continue }
                    guard let self else { break }

                    transactionsByID[transaction.id] = transaction
                    continuation.yield(makeTransaction(from: transaction))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func finish(transactionID: UInt64) async {
        guard let transaction = transactionsByID.removeValue(forKey: transactionID) else {
            return
        }
        await transaction.finish()
    }

    func sync() async throws {
        try await StoreKit.AppStore.sync()
    }

    private func appendVerified(
        _ verification: VerificationResult<StoreKit.Transaction>,
        to entitlements: inout [PatronageTransaction]
    ) {
        guard case .verified(let transaction) = verification else { return }
        transactionsByID[transaction.id] = transaction
        entitlements.append(makeTransaction(from: transaction))
    }

    private func makeTransaction(
        from transaction: StoreKit.Transaction
    ) -> PatronageTransaction {
        PatronageTransaction(
            id: transaction.id,
            productID: transaction.productID,
            quantity: transaction.purchasedQuantity
        )
    }
}

enum AppSourceDetector {
    static func isAppStoreBuild(
        receiptURL: URL? = Bundle.main.appStoreReceiptURL,
        fileExists: (String) -> Bool = FileManager.default.fileExists(atPath:)
    ) -> Bool {
        guard let receiptURL else { return false }
        return fileExists(receiptURL.path)
    }
}

@MainActor
final class PatronageService: ObservableObject {
    @Published private(set) var availableProductIDs: Set<String> = []
    @Published private(set) var isProcessing = false

    private let store: PatronageStore
    private let isAppStoreBuild: () -> Bool
    private let presentMessage: (AppMessage) -> Void
    private var updatesTask: Task<Void, Never>?

    init(
        store: PatronageStore = StoreKitPatronageStore(),
        isAppStoreBuild: @escaping () -> Bool = {
            AppSourceDetector.isAppStoreBuild()
        },
        presentMessage: @escaping (AppMessage) -> Void = AppMessageCenter.shared.post
    ) {
        self.store = store
        self.isAppStoreBuild = isAppStoreBuild
        self.presentMessage = presentMessage
    }

    func start() {
        AppSettings.setInstalledFromAppStore(isAppStoreBuild())
        guard updatesTask == nil else { return }

        updatesTask = Task { [weak self] in
            guard let self else { return }
            await loadProducts()
            guard !Task.isCancelled else { return }
            _ = await refreshEntitlements()
            guard !Task.isCancelled else { return }

            for await transaction in store.transactionUpdates() {
                guard !Task.isCancelled else { break }
                await process(transaction)
            }
        }
    }

    func stop() {
        updatesTask?.cancel()
        updatesTask = nil
    }

    func isProductAvailable(_ productID: String) -> Bool {
        availableProductIDs.contains(productID)
    }

    func purchase(_ productID: String) async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        do {
            if !isProductAvailable(productID) {
                await loadProducts()
            }
            guard isProductAvailable(productID) else {
                throw PatronageStoreError.productUnavailable
            }

            switch try await store.purchase(productID: productID) {
            case .purchased(let transaction):
                await process(transaction)
                presentMessage(.patronagePurchaseSucceeded)
            case .pending, .cancelled:
                break
            }
        } catch {
            showPurchaseError(error)
        }
    }

    func restore() async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        do {
            try await store.sync()
            let entitlementCount = await refreshEntitlements()
            presentMessage(
                entitlementCount > 0 ? .patronageRestoreSucceeded : .patronageRestoreEmpty
            )
        } catch {
            showPurchaseError(error)
        }
    }

    @discardableResult
    func refreshEntitlements() async -> Int {
        let entitlements = await store.currentEntitlements()
        let recognized = entitlements.filter {
            PatronageProducts.duration(for: $0.productID) != nil
        }
        let preserveExistingDuration =
            AppSettings.processedPatronageTransactionIDs.isEmpty
            && AppSettings.patronageDuration > 0

        for transaction in recognized {
            if preserveExistingDuration {
                AppSettings.markPatronageTransactionProcessed(id: transaction.id)
                await store.finish(transactionID: transaction.id)
            } else {
                await process(transaction)
            }
        }

        return recognized.count
    }

    private func loadProducts() async {
        do {
            availableProductIDs = try await store.loadProducts(
                identifiers: PatronageProducts.all
            )
        } catch {
            availableProductIDs = []
            let errorDescription = String(describing: error)
            MeetingBarLogger.patronage.error(
                "Could not load patronage products: \(errorDescription, privacy: .private)"
            )
        }
    }

    private func process(_ transaction: PatronageTransaction) async {
        guard let months = PatronageProducts.duration(for: transaction.productID) else {
            return
        }

        AppSettings.recordPatronageTransaction(
            id: transaction.id,
            months: months,
            quantity: transaction.quantity
        )
        await store.finish(transactionID: transaction.id)
    }

    private func showPurchaseError(_ error: Error) {
        if let purchaseError = error as? Product.PurchaseError {
            switch purchaseError {
            case .purchaseNotAllowed:
                presentMessage(.patronagePaymentNotAllowed)
            case .productUnavailable:
                presentMessage(.patronageProductUnavailable)
            default:
                presentMessage(.patronageUnknownError)
            }
            return
        }

        if let storeError = error as? StoreKitError {
            switch storeError {
            case .userCancelled:
                return
            case .networkError:
                presentMessage(.patronageNetworkFailed)
            case .notAvailableInStorefront:
                presentMessage(.patronageProductUnavailable)
            default:
                presentMessage(.patronageUnknownError)
            }
            return
        }

        if let patronageError = error as? PatronageStoreError {
            switch patronageError {
            case .productUnavailable:
                presentMessage(.patronageProductUnavailable)
            case .failedVerification:
                presentMessage(.patronageUnknownError)
            }
        } else {
            presentMessage(.patronageFailure(description: error.localizedDescription))
        }
    }
}
