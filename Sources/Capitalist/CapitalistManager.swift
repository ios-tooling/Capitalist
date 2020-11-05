//
//  CapitalistManager.swift
//

import Foundation
import StoreKit
import Studio

/*

	Call CapitalistManager.instance.setup(with: Secret, productIDs: [Product IDs]) in AppDelegate.didFinishLaunching
	
*/

typealias ReceiptCompletion = ([String: Any]?) -> Void

public protocol CapitalistManagerDelegate: class {
	func didFetchProducts()
	func didPurchase(product: CapitalistManager.Product, flags: CapitalistManager.PurchaseFlag)
}

public class CapitalistManager: NSObject {
	public static let instance = CapitalistManager()

	public var purchasedProducts: [Product.ID] = []
	public var availableProducts: [Product.ID: Product] = [:]
	public var waitingPurchases: [Product.ID] = []
	public var receipt = Receipt()
	public var cacheDecryptedReceipts = true
	public var useSandbox = !Gestalt.isProductionBuild
	public var allProductIDs: [Product.ID] = []
	public var purchaseTimeOut = TimeInterval.minute * 2
	public var purchasedConsumables: [ConsumablePurchase] = []
	public weak var delegate: CapitalistManagerDelegate?
	public var subscriptionManagementURL = URL(string: "https://finance-app.itunes.apple.com/account/subscriptions")!
	
	public var state = State.idle { didSet { self.purchaseTimeOutTimer?.invalidate() }}

	private var purchaseQueue = DispatchQueue(label: "purchasing")
	private var purchaseCompletion: ((Product?, Error?) -> Void)?
	private weak var purchaseTimeOutTimer: Timer?

	public func setup(with secret: String, productIDs: [Product.ID], refreshReceipt: Bool = true) {
		SKPaymentQueue.default().add(self)
		CapitalistManager.Receipt.appSpecificSharedSecret = secret
		self.allProductIDs = productIDs
		self.receipt.loadLocal(refreshingIfRequired: false)
		self.requestProducts()
		if refreshReceipt { self.checkForPurchases() }
	}
	
	public func checkForPurchases() {
		self.receipt.refresh()
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
	
	public func restorePurchases(justUsingReceipt: Bool = true) {
		if justUsingReceipt, !Gestalt.isAttachedToDebugger {
			self.receipt.refresh()
		} else {
			SKPaymentQueue.default().restoreCompletedTransactions()
		}
	}
	
	public func product(for id: Product.ID) -> Product? {
		return self.availableProducts[id]
	}

	public func canPurchase(_ id: Product.ID) -> Bool {
		if self.state != .idle, self.state != .restoring { return false }
		guard !id.isPrepurchased, let product = self.product(for: id), product.product != nil else { return false }
		
		switch product.id.kind {
		case .consumable: return true
		case .nonConsumable: return !self.hasPurchased(id)
		case .subscription: return self.currentExpirationDate(for: [id]) == nil
		case .none: return false
		}
	}
	
	@discardableResult
	public func purchase(_ id: Product.ID, completion: ((Product?, Error?) -> Void)? = nil) -> Bool {
		guard let product = self.product(for: id), let skProduct = product.product else {
			completion?(nil, CapitalistError.productNotFound)

			Notifications.didFailToPurchaseProduct.notify(id, info: ["error": CapitalistError.productNotFound])

			return false
		}

		guard self.state == .idle else {
			completion?(product, CapitalistError.purchaseAlreadyInProgress)
			return false
		}

		self.state = .purchasing(product)
		Notifications.startingProductPurchase.notify()
		
		self.purchaseCompletion = completion
		self.purchaseQueue.async {
			if product.id.kind == .nonConsumable, self.hasPurchased(product.id) {
				self.purchaseCompletion?(product, nil)
				Notifications.didPurchaseProduct.notify(product, info: Notification.purchaseFlagsDict(.prepurchased))
				self.delegate?.didPurchase(product: product, flags: .prepurchased)
				self.state = .idle
				return
			}
					
			self.purchaseTimeOutTimer = Timer.scheduledTimer(withTimeInterval: self.purchaseTimeOut, repeats: false) { _ in
				self.failPurchase(of: product, dueTo: CapitalistError.requestTimedOut)
			}

			let payment = SKPayment(product: skProduct)
			SKPaymentQueue.default().add(payment)
		}
		
		return true
	}
	
	func recordPurchase(of product: Product, at date: Date?, restored: Bool) {
		self.purchasedProducts.append(product.id)
		if product.id.kind == .consumable, let purchasedAt = date {
			self.recordConsumablePurchase(of: product.id, at: purchasedAt)
		}

		let completion = self.purchaseCompletion
		self.purchaseCompletion = nil

		self.receipt.loadLocal(refreshingIfRequired: true) { error in
			if let err = error { print("Error when loading local receipt: \(err)") }
			if product.id.kind == .subscription {
				self.receipt.refresh() { error in
					completion?(product, nil)
					self.state = .idle
					Notifications.didPurchaseProduct.notify(product, info: Notification.purchaseFlagsDict(restored ? .restored : []))
					self.delegate?.didPurchase(product: product, flags: restored ? .restored : [])
				}
			} else {
				completion?(product, nil)
				self.state = .idle
				Notifications.didPurchaseProduct.notify(product, info: Notification.purchaseFlagsDict(restored ? .restored : []))
				self.delegate?.didPurchase(product: product, flags: restored ? .restored : [])
			}
		}
	}
	
	public func product(from id: Product.ID?) -> Product? {
		guard let id = id else { return nil }
		return self.availableProducts[id]
	}
	
	public func productID(from string: String?) -> Product.ID? {
		return self.allProductIDs.filter({ $0.rawValue == string }).first
	}
}

extension CapitalistManager: SKPaymentTransactionObserver {
	public func clearOpenTransactions() {
		let queue = SKPaymentQueue.default()
		let transactions = queue.transactions
		if transactions.isEmpty { return }
		
		print("There were \(transactions.count) pending transactions waiting to be cleared:")
		transactions.forEach {
			print($0.detailedDescription)
			queue.finishTransaction($0)
		}
	}
	
	public func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
		for transaction in transactions {
			switch transaction.transactionState {
			case .purchased, .restored:
				if let product = self.product(from: self.productID(from: transaction.payment.productIdentifier)) {
					self.recordPurchase(of: product, at: transaction.transactionDate, restored: transaction.transactionState == .restored)
					SKPaymentQueue.default().finishTransaction(transaction)
				}
				
			case .purchasing: print("Started purchase flow for \(transaction.payment.productIdentifier)")
			case .deferred: print("Purchased deferred for \(transaction.payment.productIdentifier)")
			case .failed:
				self.failPurchase(of: self.product(from: self.productID(from: transaction.payment.productIdentifier)), dueTo: transaction.error)
				SKPaymentQueue.default().finishTransaction(transaction)
				
				
			@unknown default:
				self.failPurchase(of: self.product(from: self.productID(from: transaction.payment.productIdentifier)), dueTo: transaction.error)
				SKPaymentQueue.default().finishTransaction(transaction)
			}
		}
	}
	
	func failPurchase(of product: Product?, dueTo error: Error?) {
		guard let prod = product else {
			self.purchaseCompletion = nil
			return
		}
		
		let completion = self.purchaseCompletion
		self.waitingPurchases.remove(prod.id)
		
		self.purchaseCompletion = nil

		if self.state == .purchasing(prod) {
			var userInfo: [String: Any]? = error != nil ? ["error": error!] : nil
			if let err = error as? SKError, err.code == .paymentCancelled || err.code == .paymentNotAllowed { userInfo = nil }
			self.state = .idle
			Notifications.didFailToPurchaseProduct.notify(prod, info: userInfo)
		}

		completion?(product, error)
		print("Failed to purchase \(prod), \(error?.localizedDescription ?? "no error description").")
	}
}

extension CapitalistManager: SKRequestDelegate {
	public func requestDidFinish(_ request: SKRequest) {
		switch self.state {
		case .restoring:
			self.state = .idle
			
		default: break
		}
	}
	
	public func request(_ request: SKRequest, didFailWithError error: Error) {
		switch self.state {
		case .idle:
			print("We shouldn't hit an error when we're idle.")
			
		case .fetchingProducts:
			print("Failed to fetch products: \(error)")
			self.purchaseQueue.resume()
			
		case .purchasing(let product):
			print("Failed to purchase \(product): \(error)")
			self.failPurchase(of: product, dueTo: error)
			
		case .restoring:
			print("Restore failed: \(error)")
		}
		
		self.state = .idle
		print("Error from \(request): \(error)")
	}
}

extension CapitalistManager: SKProductsRequestDelegate {
	func requestProducts(productIDs: [Product.ID]? = nil ) {
		if self.state != .idle { return }
		
		self.purchaseQueue.suspend()
		let products = productIDs ?? self.allProductIDs
		let request = SKProductsRequest(productIdentifiers: Set(products.map({ $0.rawValue })))
		request.delegate = self
		request.start()
		
	}
	
	public func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
		self.availableProducts = [:]
		response.products.forEach {
			if let prod = self.productID(from: $0.productIdentifier) {
				self.availableProducts[prod] = Product(product: $0)
			}
		}
		
		self.state = .idle
		
		self.receipt.updateCachedReceipt()
		self.purchaseQueue.resume()
		Notifications.didFetchProducts.notify()
		self.delegate?.didFetchProducts()
	}
}

extension SKPaymentTransaction {
	var detailedDescription: String {
		var text = "\(self.payment.productIdentifier) - \(self.transactionState.description)"
		
		if let date = self.transactionDate {
			text += " at \(date.localTimeString())"
		}
		
		return text
	}
}

extension SKPaymentTransactionState {
	var description: String {
		switch self {
		case .deferred: return "deferred"
		case .failed: return "failed"
		case .purchased: return "purchased"
		case .purchasing: return "purchasing"
		case .restored: return "restored"
		default: return "unknown state"
		}
	}
}

extension Error {
	public var isStoreKitCancellation: Bool {
		let err: Error? = self
		
		return (err as NSError?)?.code == 2 && (err as NSError?)?.domain == SKErrorDomain
	}
}
