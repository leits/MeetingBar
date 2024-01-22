//
//  AppStore.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 06.02.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//

import Foundation

import Defaults
import SwiftyStoreKit

enum PatronageProducts {
    static let threeMonth = "leits.MeetingBar.patronage.3Month"
    static let sixMonth = "leits.MeetingBar.patronage.6Month"
    static let twelveMonth = "leits.MeetingBar.patronage.12Month"
}

func completeStoreTransactions() {
    SwiftyStoreKit.completeTransactions(atomically: true) { purchases in
        for purchase in purchases {
            switch purchase.transaction.transactionState {
            case .purchased, .restored:
                if purchase.needsFinishTransaction {
                    SwiftyStoreKit.finishTransaction(purchase.transaction)
                }
            default:
                break
            }
        }
    }
}

func checkAppSource() {
    if SwiftyStoreKit.localReceiptData == nil {
        Defaults[.isInstalledFromAppStore] = false
    } else {
        Defaults[.isInstalledFromAppStore] = true
    }
}

func getPatronageDurationFromProductID(_ productID: String) -> Int {
    var patronageDuration = 0
    if productID == PatronageProducts.threeMonth {
        patronageDuration = 3
    } else if productID == PatronageProducts.sixMonth {
        patronageDuration = 6
    } else if productID == PatronageProducts.twelveMonth {
        patronageDuration = 12
    }
    return patronageDuration
}

func restorePatronagePurchases() {
    Defaults[.patronageDuration] = 0
    SwiftyStoreKit.restorePurchases(atomically: true) { results in
        if !results.restoreFailedPurchases.isEmpty {
            NSLog("Restore Failed: \(results.restoreFailedPurchases)")
        } else if !results.restoredPurchases.isEmpty {
            for purchase in results.restoredPurchases {
                let restorePatronageDuration = getPatronageDurationFromProductID(purchase.productId)
                Defaults[.patronageDuration] += restorePatronageDuration * purchase.quantity
            }
            sendNotification("store_patronage_title".loco(), "store_patronage_restore_success_message".loco())
        } else {
            sendNotification("store_patronage_title".loco(), "store_patronage_restore_nothing_message".loco())
        }
    }
}

func purchasePatronage(_ productID: String) {
    SwiftyStoreKit.purchaseProduct(productID, quantity: 1, atomically: true) { result in
        switch result {
        case .success:
            let purchasePatronageDuration = getPatronageDurationFromProductID(productID)
            Defaults[.patronageDuration] += purchasePatronageDuration
            sendNotification("store_patronage_title".loco(), "store_patronage_purchase_success_message".loco())
        case let .error(error):
            switch error.code {
            case .unknown:
                sendNotification("store_patronage_title".loco(), "store_patronage_purchase_unknown_message".loco())
            case .clientInvalid:
                sendNotification("store_patronage_title".loco(), "store_patronage_purchase_client_invalid_message".loco())
            case .paymentCancelled:
                break
            case .paymentInvalid:
                sendNotification("store_patronage_title".loco(), "store_patronage_purchase_payment_invalid_message".loco())
            case .paymentNotAllowed:
                sendNotification("store_patronage_title".loco(), "store_patronage_purchase_payment_not_allowed_message".loco())
            case .storeProductNotAvailable:
                sendNotification("store_patronage_title".loco(), "store_patronage_purchase_store_product_not_available_message".loco())
            case .cloudServicePermissionDenied:
                sendNotification("store_patronage_title".loco(), "store_patronage_purchase_cloud_service_permission_denied_message".loco())
            case .cloudServiceNetworkConnectionFailed:
                sendNotification("store_patronage_title".loco(), "store_patronage_purchase_cloud_service_network_connection_failed".loco())
            case .cloudServiceRevoked:
                sendNotification("store_patronage_title".loco(), "store_patronage_purchase_cloud_service_revoked_message".loco())
            default:
                sendNotification("store_patronage_title".loco(), (error as NSError).localizedDescription)
            }
        case .deferred:
            break
        }
    }
}
