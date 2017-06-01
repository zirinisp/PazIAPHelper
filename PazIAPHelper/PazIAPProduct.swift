//
//  PazIAPProduct.swift
//  PazIAPHelper
//
//  Created by Pantelis Zirinis on 29/05/2017.
//  Copyright © 2017 Pantelis Zirinis. All rights reserved.
//

import Foundation
import StoreKit
import SwiftyStoreKit


open class PazIAPProduct: NSObject, NSCoding, SKProductsRequestDelegate, SKPaymentTransactionObserver {
    public enum UpdateNotification {
        /// Posted when product request is successful/failed
        case ProductRequest(success: Bool)
        /// Posted when product request is successful/failed
        case ProductPurchase(success: Bool)
        
        /// This is the key to access more information on a successfull or failed notification
        public static var ProductPurchaseTransactionKey = "PazIAPProduct.UpdateNotificationProductPurchaseTransactionKey"
        
        public static var ProductPurchaseErrorKey = "PazIAPProduct.UpdateNotificationProductPurchaseErrorKey"
        
        public var name: Notification.Name {
            switch self {
            case .ProductPurchase(let success):
                return Notification.Name(success ? "PazIAPProduct.UpdateNotificationProductRequestSuccess" : "PazIAPProduct.UpdateNotificationProductRequestFailed")
            case .ProductRequest(let success):
                return Notification.Name(success ? "PazIAPProduct.UpdateNotificationProductPurchaseSuccess" : "PazIAPProduct.UpdateNotificationProductPurchaseFailed")
            }
        }
    }
    
    public enum ProductType: Int {
        case oneOff
        case autoRenewable
    }
    
    public enum PurchaseError: Swift.Error {
        case notVerified
        case expired(date: Date?)
        
        public var localizedDescription: String {
            switch self {
            case .notVerified:
                return "Purchase Was Not Verified"
            case .expired(let date):
                if let date = date {
                    return "Purchase expired on \(date)"
                } else {
                    return "Purchase expired"
                }
            }
        }
    }
    
    open var title: String?
    
    open var subtitle: String?
    
    /// Product ID registered with apple servers
    open var productIdentifier: String
    
    open var productType: ProductType
    
    open var expiryDate: Date? {
        didSet {
            guard let oldDate = oldValue, let newDate = self.expiryDate else {
                self.autoRenewCheck = false
                return
            }
            if newDate.isLaterThan(oldDate) {
                self.autoRenewCheck = false
            }
        }
    }

    // This is used to run auto renew check only once
    var autoRenewCheck: Bool
    
    private var _product: SKProduct?
    /// Set to automatically fetch product when product variable is nil and it is accessed
    open var autoFetch = true
    /// When the product is fetched this variable is set
    open var product: SKProduct? {
        get {
            if let product = self._product {
                return product
            } else {
                if self.autoFetch {
                    self.fetchProduct()
                }
                return nil
            }
        }
    }
    
    /// Compare
    open override func isEqual(_ object: Any?) -> Bool {
        guard let product = object as? PazIAPProduct else {
            return false
        }
        return self.productIdentifier == product.productIdentifier
    }
    
    /// When was the product last fetched
    open var lastFetch: Date?
    
    /// Dictionary to store any relevant information
    open var userInfo = [String: AnyObject]()
    
    /// Used to store purchases on keychain. If changed all previous purchases will become inactive.
    open var keychainPassword: String? = "fdjUHUK348@$%fgkgf"
    
    /// Message to display once purchase is successfull.
    open var purchaseMessage: String?
    
    /// Message to display when user is asked to make a purchase.
    open var purchasePromptMessage: String?
    
    /// Set to bypass active
    open var bypassActive: Bool = false
    
    /// Price with currency symbol, local for the user
    open var localPriceFormatted: String? {
        if let price = self.product?.price, let locale = self.product?.priceLocale {
            let numberFormatter = NumberFormatter()
            numberFormatter.formatterBehavior = NumberFormatter.Behavior.behavior10_4
            numberFormatter.numberStyle = NumberFormatter.Style.currency
            numberFormatter.locale = locale
            let formattedPrice = numberFormatter.string(from: price)
            return formattedPrice
        } else {
            return nil
        }
    }
    
    /// Local price
    open var localPrice: Double? {
        return self.product?.price.doubleValue
    }
    
    open var localizedTitle: String? {
        return self.product?.localizedTitle
    }
    
    open var localizedDescription: String? {
        return self.product?.localizedDescription
    }
    
    private var _active: Bool = false
    /// Returns wheather the product has been purchased or not
    public var active: Bool {
        get {
            if self.bypassActive {
                return true
            }
            if self._active == false {
                return false
            }
            switch self.productType {
            case .oneOff:
                return self._active
            case .autoRenewable:
                guard let expiryDate = self.expiryDate, expiryDate.isLaterThan(Date()) else {
                    if self.autoRenewCheck {
                        self.verifyAndActivate()
                        self.autoRenewCheck = false
                    }
                    return false
                }
                return true
            }
        }
    }
    
    open private (set) var fetchingProduct = false
    
    open private (set) var purchasingProduct = false
    
    /// Helper variable to determine what level the user has unlocked. Premium = 1, Pro = 2, etc
    open var level = 0
    
    /// Init
    public init(title: String?, subtitle: String?, productIdentifier: String, productType: ProductType, expiryDate: Date?, autoRenewCheck: Bool, purchasePromptMessage: String?, purchaseMessage: String?, level: Int) {
        self.title = title
        self.subtitle = subtitle
        self.productIdentifier = productIdentifier
        self.productType = productType
        self.purchasePromptMessage = purchasePromptMessage
        self.purchaseMessage = purchaseMessage
        self.level = level
        self.expiryDate = expiryDate
        self.autoRenewCheck = autoRenewCheck
        super.init()
        self.updateActive()
        SKPaymentQueue.default().add(self)
    }
    
    deinit {
        SKPaymentQueue.default().remove(self)
    }
    
    public convenience init(title: String, subtitle: String, productIdentifier: String, productType: ProductType, expiryDate: Date?, autoRenewCheck: Bool, purchasePromptMessage: String?, purchaseMessage: String?) {
        self.init(title: title, subtitle: subtitle, productIdentifier: productIdentifier, productType: productType, expiryDate: expiryDate, autoRenewCheck: autoRenewCheck, purchasePromptMessage: purchasePromptMessage, purchaseMessage: purchaseMessage, level: 0)
    }
    
    open func fetchProduct() {
        if self.fetchingProduct {
            return
        }
        self.fetchingProduct = true
        let productsRequest = SKProductsRequest(productIdentifiers: Set([self.productIdentifier]))
        productsRequest.delegate = self
        productsRequest.start()
    }
    
    /// Should be used only when a fetch is made externaly. Ex. from IAPHelper
    open func setFetchingProduct() {
        self.fetchingProduct = true
    }
    
    open func purchaseProduct() {
        if self.purchasingProduct {
            return
        }
        
        if let product = self.product {
            self.purchasingProduct = true
            let payment = SKPayment(product: product)
            SKPaymentQueue.default().add(payment)
        } else {
            NotificationCenter.default.post(name: PazIAPProduct.UpdateNotification.ProductPurchase(success: false).name, object: self)
        }
    }
    
    /// Activates product. Should be used only when valid purchase is made.
    func activateProduct() {
        guard let passwordData = self.keychainPassword?.data(using: String.Encoding.utf8) else {
            print("Error not password data")
            return
        }
        
        var keychainQuery = self.keychainDictionary()
        keychainQuery[kSecValueData as String] = passwordData as AnyObject?
        
        // Delete any existing items
        SecItemDelete(keychainQuery as CFDictionary)
        
        // Add the new keychain item
        let status: OSStatus = SecItemAdd(keychainQuery as CFDictionary, nil)
        
        // Check that it worked ok
        print("In App Purchase Activated: \(status)")
        
        self.updateActive()
    }
    
    /// Checks keychain wheather purchase has been made and updated product
    open func updateActive() {
        var keychainQuery = self.keychainDictionary()
        keychainQuery[kSecReturnData as String] = kCFBooleanTrue
        keychainQuery[kSecMatchLimit as String] = kSecMatchLimitOne
        
        var result :AnyObject?
        
        // Search
        let status = withUnsafeMutablePointer(to: &result) {
            SecItemCopyMatching(keychainQuery as CFDictionary, UnsafeMutablePointer($0))
        }
        
        if status == noErr {
            if let data = result as? NSData {
                let password = String(data: data as Data, encoding: String.Encoding.utf8)
                self._active = self.keychainPassword == password
            }
        } else {
            self._active = false
        }
    }
    
    func keychainDictionary() -> [String: AnyObject] {
        let keychainDictionary: [String: AnyObject] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.productIdentifier as AnyObject,
            kSecAttrAccount as String: Bundle.main.bundleIdentifier! as AnyObject
        ]
        return keychainDictionary
    }
    
    /// Should be used only when we want to delete the purchase from memory
    func resetPurchase() {
        guard let passwordData = self.keychainPassword?.data(using: String.Encoding.utf8) else {
            print("could not reset no password found")
            return
        }
        
        var keychainQuery = self.keychainDictionary()
        keychainQuery[kSecValueData as String] = passwordData as AnyObject?
        
        // Delete any existing items
        SecItemDelete(keychainQuery as CFDictionary)
        self.updateActive()
    }
    
    // MARK: SKProductsRequestDelegate
    open func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        self.fetchingProduct = false
        for product in response.products {
            if product.productIdentifier == self.productIdentifier {
                self._product = product
                self.lastFetch = Date()
                NotificationCenter.default.post(name: PazIAPProduct.UpdateNotification.ProductRequest(success: true).name, object: self)
                return
            }
        }
        NotificationCenter.default.post(name: PazIAPProduct.UpdateNotification.ProductRequest(success: false).name, object: self)
    }
    
    // MARK: SKPaymentTransactionObserver
    open func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        for transaction in transactions {
            if transaction.payment.productIdentifier == self.productIdentifier {
                switch transaction.transactionState {
                case .failed:
                    self.purchasingProduct = false
                    print("Purchase failed \(self.productIdentifier)")
                    NotificationCenter.default.post(name: PazIAPProduct.UpdateNotification.ProductPurchase(success: false).name, object: self, userInfo: [PazIAPProduct.UpdateNotification.ProductPurchaseTransactionKey : transaction])
                    SKPaymentQueue.default().finishTransaction(transaction)
                case .purchased, .restored:
                    self.purchasingProduct = false
                    self.verifyAndActivate(transaction)
                case .purchasing, .deferred:
                    break
                }
            }
        }
    }
    
    // MARK: Verify Purchase
    open func verifyAndActivate(_ transaction: SKPaymentTransaction? = nil) {
        func activate() {
            self.activateProduct()
            print("Purchase successful \(self.productIdentifier)")
            if let transaction = transaction {
                NotificationCenter.default.post(name: PazIAPProduct.UpdateNotification.ProductPurchase(success: true).name, object: self, userInfo: [PazIAPProduct.UpdateNotification.ProductPurchaseTransactionKey : transaction])
                SKPaymentQueue.default().finishTransaction(transaction)
            }
        }
        func fail(error: Error, finishTransaction: Bool) {
            if let transaction = transaction {
                NotificationCenter.default.post(name: PazIAPProduct.UpdateNotification.ProductPurchase(success: false).name, object: self, userInfo: [PazIAPProduct.UpdateNotification.ProductPurchaseTransactionKey : transaction, PazIAPProduct.UpdateNotification.ProductPurchaseErrorKey: error])
                if finishTransaction {
                    SKPaymentQueue.default().finishTransaction(transaction)
                }
            } else {
                NotificationCenter.default.post(name: PazIAPProduct.UpdateNotification.ProductPurchase(success: false).name, object: self, userInfo: [PazIAPProduct.UpdateNotification.ProductPurchaseErrorKey: error])
            }
        }
        // Check is shared secret is available. If not skip the verification
        guard let sharedSecret = PazIAPHelper.shared.sharedSecret else {
            activate()
            return
        }
        let appleValidator = AppleReceiptValidator(service: .production)
        SwiftyStoreKit.verifyReceipt(using: appleValidator, password: sharedSecret) { [weak self] result in
            guard let strongSelf = self else {
                return
            }
            switch result {
            case .success(let receipt):
                switch strongSelf.productType {
                case .oneOff:
                    // Verify the purchase of Consumable or NonConsumable
                    let purchaseResult = SwiftyStoreKit.verifyPurchase(
                        productId: strongSelf.productIdentifier,
                        inReceipt: receipt)
                    
                    switch purchaseResult {
                    case .purchased(let receiptItem):
                        print("Product is purchased: \(receiptItem)")
                        activate()
                    case .notPurchased:
                        print("The user has never purchased \(strongSelf.productIdentifier)")
                        let error = PurchaseError.notVerified
                        fail(error: error, finishTransaction: true)
                    }
                case .autoRenewable:
                    // Verify the purchase of a Subscription
                    let purchaseResult = SwiftyStoreKit.verifySubscription(
                        type: .autoRenewable, // or .nonRenewing (see below)
                        productId: strongSelf.productIdentifier,
                        inReceipt: receipt)
                    
                    switch purchaseResult {
                    case .purchased(let expiryDate, _):
                        print("Product is valid until \(expiryDate)")
                        strongSelf.expiryDate = expiryDate
                        activate()
                    case .expired(let expiryDate, _):
                        print("Product is expired since \(expiryDate)")
                        strongSelf.expiryDate = expiryDate
                        let error = PurchaseError.expired(date: expiryDate)
                        fail(error: error, finishTransaction: true)
                    case .notPurchased:
                        print("The user has never purchased this product")
                        let error = PurchaseError.notVerified
                        fail(error: error, finishTransaction: true)
                    }
                }
                
            case .error(let error):
                fail(error: error, finishTransaction: false)
                print("Receipt verification failed: \(error)")
            }
        }
        
    }
    
    // MARK: NSCoder
    open func encode(with aCoder: NSCoder) {
        aCoder.encode(self.title, forKey:"name")
        aCoder.encode(self.subtitle, forKey:"subtitle")
        aCoder.encode(self.productIdentifier, forKey:"productID")
        aCoder.encode(self.purchaseMessage, forKey: "puchaseMessage")
        aCoder.encode(self.purchasePromptMessage, forKey:  "purchasePromptMessage")
        aCoder.encode((self.level as Int?), forKey: "level")
        aCoder.encode(self.userInfo, forKey: "userInfo")
        aCoder.encode(self.keychainPassword, forKey: "keychainPassword")
        aCoder.encode(self.productType.rawValue, forKey: "productType")
        aCoder.encode(self.expiryDate, forKey: "expiryDate")
        aCoder.encode(self.autoRenewCheck, forKey: "autoRenewCheck")
    }
    
    public convenience required init?(coder aDecoder: NSCoder) {
        guard let level = aDecoder.decodeObject(forKey: "level") as? Int else {
            return nil
        }
        guard let productIdentifier = (aDecoder.decodeObject(forKey: "productID") as? String) else {
            return nil
        }

        let title = (aDecoder.decodeObject(forKey: "name") as? String)
        let subtitle = (aDecoder.decodeObject(forKey: "subtitle") as? String)
        let purchaseMessage = (aDecoder.decodeObject(forKey: "purchaseMessage") as? String)
        let purchasePromptMessage = (aDecoder.decodeObject(forKey: "purchasePromptMessage") as? String)
        let productType = ProductType(rawValue: (aDecoder.decodeObject(forKey: "productType") as? Int) ?? 0) ?? ProductType.oneOff
        let expiryDate = aDecoder.decodeObject(forKey: "expiryDate") as? Date
        let autoRenewCheck = (aDecoder.decodeObject(forKey: "autoRenewCheck") as? Bool) ?? true
        self.init(title: title, subtitle: subtitle, productIdentifier: productIdentifier, productType: productType, expiryDate: expiryDate, autoRenewCheck: autoRenewCheck, purchasePromptMessage: purchasePromptMessage, purchaseMessage: purchaseMessage, level: level)
        if let userInfo = aDecoder.decodeObject(forKey: "userInfo") as? [String: AnyObject] {
            self.userInfo = userInfo
        }
        if let password = aDecoder.decodeObject(forKey: "keychainPassword") as? String {
            self.keychainPassword = password
        }
        self.updateActive()
    }
}
