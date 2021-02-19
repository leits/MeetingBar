//
//  Store.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 06.02.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//

import Foundation

import Defaults
import SwiftyStoreKit

struct patronageProducts {
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

func getPatronageDurationFromProductID(_ ProductID: String) -> Int {
    var patronageDuration = 0
    if ProductID == patronageProducts.threeMonth {
        patronageDuration = 3
    } else if ProductID == patronageProducts.sixMonth {
        patronageDuration = 6
    } else if ProductID == patronageProducts.twelveMonth {
        patronageDuration = 12
    }
    return patronageDuration
}

func restorePatronagePurchases() {
    Defaults[.patronageDuration] = 0
    SwiftyStoreKit.restorePurchases(atomically: true) { results in
        if !results.restoreFailedPurchases.isEmpty {
            print("Restore Failed: \(results.restoreFailedPurchases)")
        } else if !results.restoredPurchases.isEmpty {
            for purchase in results.restoredPurchases {
                let restorePatronageDuration = getPatronageDurationFromProductID(purchase.productId)
                Defaults[.patronageDuration] += restorePatronageDuration * purchase.quantity
            }
            sendNotification("MeetingBar Patronage", "Successfully restored")
        } else {
            sendNotification("MeetingBar Patronage", "Nothing to Restore")
        }
    }
}

func purchasePatronage(_ productID: String) {
    SwiftyStoreKit.purchaseProduct(productID, quantity: 1, atomically: true) { result in
        switch result {
        case .success:
            let purchasePatronageDuration = getPatronageDurationFromProductID(productID)
            Defaults[.patronageDuration] += purchasePatronageDuration
            sendNotification("MeetingBar Patronage", "Successfully purchased. Thanks for support!")
        case .error(let error):
            switch error.code {
            case .unknown:
                sendNotification("MeetingBar Patronage", "Unknown error. Please contact support")
            case .clientInvalid:
                sendNotification("MeetingBar Patronage", "Not allowed to make the payment")
            case .paymentCancelled:
                break
            case .paymentInvalid:
                sendNotification("MeetingBar Patronage", "The purchase identifier was invalid")
            case .paymentNotAllowed:
                sendNotification("MeetingBar Patronage", "The device is not allowed to make the payment")
            case .storeProductNotAvailable:
                sendNotification("MeetingBar Patronage", "The product is not available in the current storefront")
            case .cloudServicePermissionDenied:
                sendNotification("MeetingBar Patronage", "Access to cloud service information is not allowed")
            case .cloudServiceNetworkConnectionFailed:
                sendNotification("MeetingBar Patronage", "Could not connect to the network")
            case .cloudServiceRevoked:
                sendNotification("MeetingBar Patronage", "User has revoked permission to use this cloud service")
            default:
                sendNotification("MeetingBar Patronage", (error as NSError).localizedDescription)
            }
        }
    }
}
