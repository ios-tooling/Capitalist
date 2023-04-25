//
//  Capitalist.swift
//

import Foundation
import StoreKit

/// Call Capitalist.instance.setup(with: Secret, productIDs: [Product IDs]) in AppDelegate.didFinishLaunching

public struct PurchaseDetails {
	public let flags: Capitalist.PurchaseFlag
	public let transactionID: String?
	public let originalTransactionID: String?
	public let expirationDate: Date?
}

public protocol CapitalistDelegate: AnyObject {
	func didFetchProducts()
	func didPurchase(product: Capitalist.Product, details: PurchaseDetails)
	func didFailToPurchase(productID: Capitalist.Product.ID, error: Error)
}

public protocol CapitalistReceiptDelegate: AnyObject {
	func didDecodeReceipt()
}

public class Capitalist: NSObject {
	public static let instance = Capitalist()
	private override init() { super.init() }
	
	public var purchasedProducts: [Product.ID] = []
	public var availableProducts: [Product.ID: Product] = [:]
	public var waitingPurchases: [Product.ID] = []
	public var receipt: Receipt!
	public var cacheDecryptedReceipts = true
	public var useSandbox = (Capitalist.distribution != .appStore && Capitalist.distribution != .testflight)
	public var allProductIDs: [Product.ID] = []
	public var purchaseTimeOut: TimeInterval = 120
	public var purchasedConsumables: [ConsumablePurchase] = []
	public var loggingOn = false
	public var subscriptionManagementURL = URL(string: "https://finance-app.itunes.apple.com/account/subscriptions")!
	public var productFetchError: Error?
	public var reportedError: Error? { didSet { self.objectChanged() }}
	public var receiptOverride: ReceiptOverride?
	public var hasSales = false
	public var storeExpirationDatesInDefaults = false
	public var useStoreKit2 = false

	public var state = State.idle { didSet { self.purchaseTimeOutTimer?.invalidate() }}
	
	weak var delegate: CapitalistDelegate?
	private var isSetup = false
	internal var purchaseQueue = DispatchQueue(label: "purchasing")
	internal let processingQueue = DispatchQueue(label: "capitalistProcessingQueue")
	internal var purchaseCompletion: ((Product?, Error?) -> Void)?
	internal weak var purchaseTimeOutTimer: Timer?
	internal var productsRequest: ProductFetcher?
	internal var pendingProducts: [Product.ID]?
	
	public var currentReceiptData: Data? { receipt.receiptData }
	
	public func setup(delegate: CapitalistDelegate, with secret: String? = nil, productIDs: [Product.ID], refreshReceipt: Bool = false, validatingReceiptWithServer: Bool = true, receiptOverride: ReceiptOverride? = nil, useStoreKit2: Bool = true) {
		if isSetup {
			print("Capitalist.setup() should only be called once.")
			return
		}
		
		if #available(iOS 15, macOS 12, *), useStoreKit2 {
			self.useStoreKit2 = true
			startStoreKit2Listener()
		}
		if let over = receiptOverride { self.receiptOverride = over }
		isSetup = true
		self.delegate = delegate
		SKPaymentQueue.default().add(self)
		Capitalist.Receipt.appSpecificSharedSecret = secret
		allProductIDs = productIDs
		receipt = Receipt(validating: validatingReceiptWithServer)
		requestProducts()
		if refreshReceipt { checkForPurchases() }
	}
	
	public func update(productIDs: [Product.ID]) {
		if Set(productIDs) == Set(allProductIDs) { return }
		
		requestProducts(productIDs: productIDs)
	}
	
	public func checkForPurchases() {
		self.receipt.refresh()
	}
	
	@available(iOS 14.0, *)
	public func presentCodeRedemptionSheet() {
		#if os(iOS)
		SKPaymentQueue.default().presentCodeRedemptionSheet()
		#endif
	}
	
	public func hasPurchased(_ product: Product.ID) -> Bool {
		return self.purchasedProducts.contains(product)
	}
	
	func isPurchasing(_ product: Product.ID? = nil, products: [Product.ID]? = nil) -> Bool {
		if let prod = product {
			return self.waitingPurchases.contains(prod)
		} else {
			let productIDs = products ?? self.allProductIDs
			for prod in productIDs { if self.waitingPurchases.contains(prod) { return true } }
		}
		return false
	}
	
	public func subscriptionState(of products: [Product.ID]? = nil) -> Product.SubscriptionState {
		let productIDs = products ?? self.allProductIDs
		
		if let validUntil = self.currentExpirationDate(for: productIDs) {
			if validUntil > Date() {
				if self.isInTrial(for: productIDs) { return .trial(validUntil) }
				return .valid(validUntil)
			}
			
			if self.isPurchasing(products: products) { return .purchasing }
			return .expired(validUntil)
		}
		
		if self.isPurchasing(products: products) { return .purchasing }
		return .none
	}

	public var activeSubscriptions: [Capitalist.Product] {
		Array(availableProducts.values).filter { $0.isSubscriptionActive }
	}
	
	public func restorePurchases(justUsingReceipt: Bool = true) {
		if justUsingReceipt {
			self.receipt.refresh()
		} else {
			SKPaymentQueue.default().restoreCompletedTransactions()
		}
	}
	
	public subscript(id: Product.ID?) -> Product? {
		guard let id else { return nil }
		return availableProducts[id]
	}
	
	public subscript(string: String?) -> Product? {
		guard let id = productID(from: string) else { return nil }
		return self[id]
	}
	
	public func productID(from string: String?) -> Product.ID? {
		return self.allProductIDs.filter({ $0.rawValue == string }).first
	}
	
	func addAvailableProduct(_ product: Capitalist.Product?) {
		guard let product else { return }
		
		processingQueue.async { self._addAvailableProduct(product) }
	}
	
	func _addAvailableProduct(_ product: Capitalist.Product) {
		
		if !allProductIDs.contains(product.id) { allProductIDs.append(product.id) }

		if let current = availableProducts[product.id] {
			availableProducts[product.id]?.info = product.info ?? current.info
			availableProducts[product.id]?.product = product.product ?? current.product
			availableProducts[product.id]?.product2 = product.product2 ?? current.product2
			availableProducts[product.id]?.recentPurchaseDate = product.recentPurchaseDate ?? current.recentPurchaseDate
			availableProducts[product.id]?.recentTransactionID = product.recentTransactionID ?? current.recentTransactionID
			availableProducts[product.id]?.expirationDate = product.expirationDate ?? current.expirationDate
			availableProducts[product.id]?.onDeviceExpirationDate = product.onDeviceExpirationDate ?? current.onDeviceExpirationDate
		} else {
			availableProducts[product.id] = product
		}
	}
	
	public func isProductAvailable(_ id: Product.ID) -> Bool { availableProducts[id]?.product != nil || availableProducts[id]?.product2 != nil }
	
	public func canPurchase(_ id: Product.ID) -> Bool {
		if self.state != .idle, self.state != .restoring { return false }
		guard !id.isPrepurchased, let product = self[id], product.isPurchaseable else { return false }
		
		switch product.id.kind {
		case .consumable: return true
		case .nonConsumable: return !self.hasPurchased(id)
		case .subscription: return self.currentExpirationDate(for: [id]) == nil
		case .none: return false
		case .notSet: return false
		}
	}
	
	func recordPurchase(of product: Product, at date: Date?, expirationDate: Date?, restored: Bool, transactionID: String?, originalTransactionID: String?) {
		if !purchasedProducts.contains(product.id) || product.id.kind == .consumable { self.purchasedProducts.append(product.id) }
		
		if let purchasedAt = date {
			switch product.id.kind {
			case .consumable:
				self.recordConsumablePurchase(of: product.id, at: purchasedAt)
				
			case .subscription:
				availableProducts[product.id]?.recentPurchaseDate = purchasedAt
				availableProducts[product.id]?.expirationDate = expirationDate
				availableProducts[product.id]?.recentTransactionID = transactionID
			default: break
			}
		}
		
		if product.id.kind == .consumable, let purchasedAt = date {
			self.recordConsumablePurchase(of: product.id, at: purchasedAt)
		}
		
		let completion = self.purchaseCompletion
		let purchased = availableProducts[product.id] ?? product
		availableProducts[product.id]?.recentTransactionID = transactionID
		self.purchaseCompletion = nil
		
		self.receipt.loadBundleReceipt { error in
			if let err = error {
				print("Error when loading local receipt: \(err)")
			} else {
				self.state = .idle
				var dict = Notification.purchaseFlagsDict(restored ? .restored : [])
				if let transactionID { dict["transactionID"] = transactionID }
				NotificationCenter.default.post(name: Notifications.didPurchaseProduct, object: purchased, userInfo: dict)
				#if targetEnvironment(simulator)
					self.saveLocalExpirationDate(for: purchased)
				#else
					if self.receipt.receiptDecodeFailed {
						self.saveLocalExpirationDate(for: purchased)
					} else {
						self.clearLocalExpirationDate(for: purchased)
					}
				#endif
			}
			DispatchQueue.main.async {
				completion?(purchased, nil)
				self.delegate?.didPurchase(product: purchased, details: PurchaseDetails(flags: restored ? .restored : [], transactionID: transactionID, originalTransactionID: originalTransactionID, expirationDate: expirationDate))
				self.objectChanged()
			}
		}
	}
}

#if canImport(Combine)

	@available(OSX 10.15, iOS 13.0, tvOS 13, watchOS 6, *)
	extension Capitalist: ObservableObject {
	}

	extension Capitalist {
		 func objectChanged() {
			  if #available(OSX 10.15, iOS 13.0, tvOS 13, watchOS 6, *) {
				  if Thread.isMainThread {
					  objectWillChange.send()
				  } else {
					  Task { await MainActor.run { objectWillChange.send() }}
				  }
			  }
		 }
	}
#else
extension Capitalist {
	func objectChanged() { }
}
#endif
