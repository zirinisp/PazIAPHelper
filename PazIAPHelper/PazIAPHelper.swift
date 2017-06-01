//
//  PazIAPHelper.swift
//  PazIAPHelper
//
//  Created by Pantelis Zirinis on 29/05/2017.
//  Copyright © 2017 Pantelis Zirinis. All rights reserved.
//

import Foundation
import StoreKit
import SwiftyStoreKit

@available(iOS 8.0, *)
open class PazIAPHelper: NSObject, SKPaymentTransactionObserver, SKProductsRequestDelegate {
    
    public enum UpdateNotification {
        /// Posted when one or some of the products become available after a product request to the App Store
        case ProductsAvailable
        /// POsted after a fetch all products request is completed.
        case ProductsRequestCompleted
        /// Posted when product is purchase/restored
        case ActiveProducts
        /// Posted when products are restored from App Store
        case RestoredProductsAppStore
        
        public var name: Notification.Name {
            switch self {
            case .ProductsAvailable:
                return Notification.Name("PazIAPHelper.UpdateNotificationProductsAvailable")
            case .ProductsRequestCompleted:
                return  Notification.Name("PazIAPHelper.UpdateNotificationProductsRequestCompleted")
            case .ActiveProducts:
                return Notification.Name("PazIAPHelper.UpdateNotificationActiveProducts")
            case .RestoredProductsAppStore:
                return Notification.Name("PazIAPHelper.UpdateNotificationRestoredProductsAppStore")
            }
        }
    }
    
    private static var _shared: PazIAPHelper = {
        let shared = PazIAPHelper()
        shared.restoreProductsFromMemery()
        #if !os(OSX) && !os(Linux)
            NotificationCenter.default.addObserver(forName: NSNotification.Name.UIApplicationDidEnterBackground, object: nil, queue: OperationQueue.main, using: { [unowned shared] (notification) -> Void in
                shared.saveProductsToMemory()
            })
        #endif
        return shared
    }()
    
    open class var shared: PazIAPHelper {
        // this way we can easily subclass and change the shared.
        return PazIAPHelper._shared
    }
    
    public override init() {
        self.products = Set<PazIAPProduct>()
        super.init()
        NotificationCenter.default.addObserver(forName: PazIAPProduct.UpdateNotification.ProductPurchase(success: true).name, object: nil, queue: nil) { [weak self] (notification) in
            guard let strongSelf = self else {
                return
            }
            guard let product = notification.object as? PazIAPProduct, strongSelf.products.contains(product) else {
                return
            }
            NotificationCenter.default.post(name: PazIAPHelper.UpdateNotification.ActiveProducts.name, object: strongSelf, userInfo: notification.userInfo)
        }
        NotificationCenter.default.addObserver(forName: PazIAPProduct.UpdateNotification.ProductRequest(success: true).name, object: nil, queue: nil) { [weak self] (notification) in
            guard let strongSelf = self else {
                return
            }
            guard let product = notification.object as? PazIAPProduct, strongSelf.products.contains(product) else {
                return
            }
            NotificationCenter.default.post(name: PazIAPHelper.UpdateNotification.ProductsAvailable.name, object: strongSelf)
        }
    }
    
    public var sharedSecret: String?
    public var environment: AppleReceiptValidator.VerifyReceiptURLType = (AppConfig.appConfiguration.rawValue == AppConfiguration.AppStore.rawValue) ? .production : .sandbox
    
    public func canMakePayments() -> Bool {
        return SKPaymentQueue.canMakePayments()
    }
    
    open func isStoreReachable() -> Bool {
        // check connection
        let hostname = "appstore.com"
        let hostinfo = gethostbyname(hostname)
        return hostinfo != nil
    }
    
    open var products: Set<PazIAPProduct>
    
    open func getProduct(withID productID: String) -> PazIAPProduct? {
        for product in self.products {
            if product.productIdentifier == productID {
                return product
            }
        }
        return nil
    }
    
    open private (set) var fetchingProducts = false
    private var _lastFetch: Date?
    open var lastFetch: Date? {
        get {
            if let last = self._lastFetch {
                return last
            }
            // If no last fetch try to get the earliest date from the products
            var last: Date?
            for product in self.products {
                if let date = product.lastFetch {
                    if let letLast = last {
                        if date.isLaterThan(letLast) {
                            last = date
                        }
                    } else {
                        last = date
                    }
                }
            }
            return last
        }
    }
    /// Fetch all products
    open func fetchAllProducts() -> Bool {
        if self.fetchingProducts {
            return true
        }
        if self.products.count == 0 {
            return false
        }
        self.fetchingProducts = true
        
        var productIDs = [String]()
        for product in products {
                productIDs.append(product.productIdentifier)
        }
        let productsRequest = SKProductsRequest(productIdentifiers: Set(productIDs))
        productsRequest.delegate = self
        productsRequest.start()
        return true
    }
    
    /// Should be used only when we want to delete all purchases
    open func resetAllPurchases() {
        for product in self.products {
            product.resetPurchase()
        }
        NotificationCenter.default.post(name: PazIAPHelper.UpdateNotification.ProductsAvailable.name, object: self)
    }
    
    /// The maximum level that the user has active. 0 if none is active.
    open var level: Int {
        var level = 0
        for product in self.products {
            if product.active {
                level = MAX(level, product.level)
            }
        }
        return level
    }
    
    /// Returns the product with the maximum level that is currently active
    open var activeProduct: PazIAPProduct? {
        var levelProduct: PazIAPProduct?
        for product in self.products {
            if product.active {
                if let current = levelProduct {
                    if product.level > current.level {
                        levelProduct = product
                    }
                } else {
                    levelProduct = product
                }
            }
        }
        return levelProduct
    }
    
    // MARK: Restore Transactions from App Store
    open private (set) var restorePurchasesFromAppStoreActive = false
    /// Used to restore purchases that have been made on the app store
    open func restorePurchasesFromAppStore() {
        if self.restorePurchasesFromAppStoreActive {
            return
        }
        SKPaymentQueue.default().add(self)
        self.restorePurchasesFromAppStoreActive = true
        SKPaymentQueue.default().restoreCompletedTransactions()
    }
    
    open func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
        self.restorePurchasesFromAppStoreActive = false
        NotificationCenter.default.post(name: PazIAPHelper.UpdateNotification.RestoredProductsAppStore.name, object: self, userInfo: nil)
    }
    
    open func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error) {
        self.restorePurchasesFromAppStoreActive = false
        NotificationCenter.default.post(name: PazIAPHelper.UpdateNotification.RestoredProductsAppStore.name, object: self, userInfo: ["error": error])
    }
    // MARK: SKPaymentTransactionObserver
    open func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        // This is handled from individual products
    }
    
    // MARK: SKProductsRequestDelegate
    open func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        self.fetchingProducts = false
        self._lastFetch = Date()
        for product in self.products {
            product.productsRequest(request, didReceive: response)
        }
        NotificationCenter.default.post(name: PazIAPHelper.UpdateNotification.ProductsRequestCompleted.name, object: self)
    }

    // MARK: AppStoreReceipt
    open var appStoreReceiptData: Data? {
        guard let receiptUrl = Bundle.main.appStoreReceiptURL else {
            return nil
        }
        do {
            let receipt: Data = try Data(contentsOf:receiptUrl)
            return receipt
        } catch {
            print("Could not get receipt data")
            return nil
        }
    }

}

enum AppConfiguration: Int {
    case Debug
    case TestFlight
    case AppStore
}

struct AppConfig {
    // This is private because the use of 'appConfiguration' is preferred.
    private static let isTestFlight = Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    
    // This can be used to add debug statements.
    static var isDebug: Bool {
        #if DEBUG
            return true
        #else
            return false
        #endif
    }
    
    static var appConfiguration: AppConfiguration {
        if isDebug {
            return .Debug
        } else if isTestFlight {
            return .TestFlight
        } else {
            return .AppStore
        }
    }
}

public func == (lhs: PazIAPProduct, rhs: PazIAPProduct) -> Bool {
    return lhs.productIdentifier == rhs.productIdentifier
}

internal extension Date {
    func isLaterThan(_ date: Date) -> Bool {
        return !self.isEarlierThan(date)
    }

    func isEarlierThan(_ date: Date) -> Bool {
        return !(self.compare(date as Date) == ComparisonResult.orderedDescending)
    }
}

internal func MAX<T : Comparable>(_ a: T, _ b: T) -> T {
    if a > b {
        return a
    }
    return b
}

