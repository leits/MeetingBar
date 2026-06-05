//
//  PatronageServiceTests.swift
//  MeetingBarTests
//

import Foundation
import XCTest

import Defaults

@testable import MeetingBar

final class PatronageProductTests: XCTestCase {
    func testProductDurationsKeepExistingIdentifiers() {
        XCTAssertEqual(PatronageProducts.duration(for: PatronageProducts.threeMonth), 3)
        XCTAssertEqual(PatronageProducts.duration(for: PatronageProducts.sixMonth), 6)
        XCTAssertEqual(PatronageProducts.duration(for: PatronageProducts.twelveMonth), 12)
        XCTAssertNil(PatronageProducts.duration(for: "other"))
    }

    func testAppSourceDetectorRequiresReceiptFile() {
        let receiptURL = URL(fileURLWithPath: "/tmp/receipt")

        XCTAssertTrue(AppSourceDetector.isAppStoreBuild(
            receiptURL: receiptURL,
            fileExists: { $0 == receiptURL.path }
        ))
        XCTAssertFalse(AppSourceDetector.isAppStoreBuild(
            receiptURL: receiptURL,
            fileExists: { _ in false }
        ))
        XCTAssertFalse(AppSourceDetector.isAppStoreBuild(
            receiptURL: nil,
            fileExists: { _ in true }
        ))
    }
}

@MainActor
final class PatronageServiceTests: BaseTestCase {
    func testPurchaseRecordsAndFinishesTransactionOnce() async {
        let store = FakePatronageStore()
        let transaction = PatronageTransaction(
            id: 101,
            productID: PatronageProducts.sixMonth,
            quantity: 2
        )
        store.purchaseResult = .purchased(transaction)
        let service = makeService(store: store)

        await service.purchase(PatronageProducts.sixMonth)
        await service.purchase(PatronageProducts.sixMonth)

        XCTAssertEqual(AppSettings.patronageDuration, 12)
        XCTAssertEqual(AppSettings.processedPatronageTransactionIDs, ["101"])
        XCTAssertEqual(store.finishedTransactionIDs, [101, 101])
        XCTAssertEqual(messages.map(\.1), [
            "store_patronage_purchase_success_message".loco(),
            "store_patronage_purchase_success_message".loco()
        ])
    }

    func testInitialEntitlementRefreshPreservesExistingDuration() async {
        AppSettings.addPatronageDuration(months: 9)
        let store = FakePatronageStore()
        store.entitlements = [
            PatronageTransaction(
                id: 201,
                productID: PatronageProducts.threeMonth,
                quantity: 1
            )
        ]
        let service = makeService(store: store)

        let count = await service.refreshEntitlements()

        XCTAssertEqual(count, 1)
        XCTAssertEqual(AppSettings.patronageDuration, 9)
        XCTAssertEqual(AppSettings.processedPatronageTransactionIDs, ["201"])
        XCTAssertEqual(store.finishedTransactionIDs, [201])
    }

    func testEntitlementRefreshCreditsNewTransactionsAndIgnoresUnknownProducts() async {
        let store = FakePatronageStore()
        store.entitlements = [
            PatronageTransaction(
                id: 301,
                productID: PatronageProducts.threeMonth,
                quantity: 2
            ),
            PatronageTransaction(id: 302, productID: "other", quantity: 1)
        ]
        let service = makeService(store: store)

        let count = await service.refreshEntitlements()

        XCTAssertEqual(count, 1)
        XCTAssertEqual(AppSettings.patronageDuration, 6)
        XCTAssertEqual(AppSettings.processedPatronageTransactionIDs, ["301"])
        XCTAssertEqual(store.finishedTransactionIDs, [301])
    }

    func testRestoreSyncsAndReportsWhetherEntitlementsExist() async {
        let store = FakePatronageStore()
        store.entitlements = [
            PatronageTransaction(
                id: 401,
                productID: PatronageProducts.twelveMonth,
                quantity: 1
            )
        ]
        let service = makeService(store: store)

        await service.restore()

        XCTAssertEqual(store.syncCallCount, 1)
        XCTAssertEqual(AppSettings.patronageDuration, 12)
        XCTAssertEqual(
            messages.last?.1,
            "store_patronage_restore_success_message".loco()
        )
    }

    func testStartPersistsAppSourceAndProcessesTransactionUpdates() async {
        let store = FakePatronageStore()
        let service = makeService(store: store, isAppStoreBuild: true)

        service.start()
        await flushTasks()
        store.emit(PatronageTransaction(
            id: 501,
            productID: PatronageProducts.threeMonth,
            quantity: 1
        ))
        await flushTasks()
        service.stop()

        XCTAssertTrue(Defaults[.isInstalledFromAppStore])
        XCTAssertEqual(AppSettings.patronageDuration, 3)
        XCTAssertEqual(store.finishedTransactionIDs, [501])
    }

    func testStopCancelsTransactionUpdates() async {
        let store = FakePatronageStore()
        let service = makeService(store: store)

        service.start()
        await flushTasks()
        service.stop()
        await flushTasks()
        store.emit(PatronageTransaction(
            id: 601,
            productID: PatronageProducts.threeMonth,
            quantity: 1
        ))
        await flushTasks()

        XCTAssertEqual(AppSettings.patronageDuration, 0)
        XCTAssertTrue(store.finishedTransactionIDs.isEmpty)
    }

    private var messages: [(String, String)] = []

    private func makeService(
        store: FakePatronageStore,
        isAppStoreBuild: Bool = false
    ) -> PatronageService {
        PatronageService(
            store: store,
            isAppStoreBuild: { isAppStoreBuild },
            presentMessage: { [weak self] title, message in
                self?.messages.append((title, message))
            }
        )
    }

    private func flushTasks() async {
        for _ in 0..<10 {
            await Task.yield()
        }
    }
}

@MainActor
private final class FakePatronageStore: PatronageStore {
    var availableProductIDs = Set(PatronageProducts.all)
    var purchaseResult: PatronagePurchaseResult = .cancelled
    var entitlements: [PatronageTransaction] = []
    private(set) var finishedTransactionIDs: [UInt64] = []
    private(set) var syncCallCount = 0

    private let updates: AsyncStream<PatronageTransaction>
    private let updatesContinuation: AsyncStream<PatronageTransaction>.Continuation

    init() {
        var continuation: AsyncStream<PatronageTransaction>.Continuation?
        updates = AsyncStream { continuation = $0 }
        updatesContinuation = continuation!
    }

    func loadProducts(identifiers _: [String]) async throws -> Set<String> {
        availableProductIDs
    }

    func purchase(productID _: String) async throws -> PatronagePurchaseResult {
        purchaseResult
    }

    func currentEntitlements() async -> [PatronageTransaction] {
        entitlements
    }

    func transactionUpdates() -> AsyncStream<PatronageTransaction> {
        updates
    }

    func finish(transactionID: UInt64) async {
        finishedTransactionIDs.append(transactionID)
    }

    func sync() async throws {
        syncCallCount += 1
    }

    func emit(_ transaction: PatronageTransaction) {
        updatesContinuation.yield(transaction)
    }
}
