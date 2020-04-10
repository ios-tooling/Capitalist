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

public class CapitalistManager: NSObject {
	public static let instance = CapitalistManager()

	public var purchasedProducts: [Product.ID] = []
	public var availableProducts: [Product.ID: Product] = [:]
	public var waitingPurchases: [Product.ID] = []
	public var receipt = Receipt()
	public var useSandbox = !Gestalt.isProductionBuild
	public var allProductIDs: [Product.ID] = []
	public var purchaseTimeOut = TimeInterval.minute * 2
	
	public var state = State.idle { didSet { self.purchaseTimeOutTimer?.invalidate() }}

	private var purchaseQueue = DispatchQueue(label: "purchasing")
	private var purchaseCompletion: ((Product?, Error?) -> Void)?
	private weak var purchaseTimeOutTimer: Timer?

	public func setup(with secret: String, productIDs: [Product.ID]) {
		CapitalistManager.Receipt.appSpecificSharedSecret = secret
		self.allProductIDs = productIDs
		SKPaymentQueue.default().add(self)
		self.requestProducts()
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
	
	public func restorePurchases() {
		SKPaymentQueue.default().restoreCompletedTransactions()
	}
	
	public func product(for id: Product.ID) -> Product? {
		return self.availableProducts[id]
	}

	@discardableResult
	public func purchase(_ id: Product.ID, completion: ((Product?, Error?) -> Void)? = nil) -> Bool {
		guard let product = self.product(for: id) else {
			completion?(nil, CapitalistError.productNotFound)
			return false
		}

		guard self.state == .idle else {
			completion?(product, CapitalistError.purchaseAlreadyInProgress)
			return false
		}

		Notifications.startingProductPurchase.post()
		
		self.purchaseCompletion = completion
		self.purchaseQueue.async {
			if product.id.kind == .nonConsumable, self.hasPurchased(product.id) {
				self.purchaseCompletion?(product, nil)
				Notifications.didPurchaseProduct.post()
				return
			}
			
			self.state = .purchasing(product)
			
			self.purchaseTimeOutTimer = Timer.scheduledTimer(withTimeInterval: self.purchaseTimeOut, repeats: false) { _ in
				self.failPurchase(of: product, dueTo: CapitalistError.requestTimedOut)
			}

			let payment = SKPayment(product: product.product)
			SKPaymentQueue.default().add(payment)
		}
		
		return true
	}
	
	func recordPurchase(of product: Product) {
		self.purchasedProducts.append(product.id)

		let completion = self.purchaseCompletion
		self.purchaseCompletion = nil

		self.receipt.loadLocal() { error in
			if let err = error { print("Error when loading local receipt: \(err)") }
			if product.id.kind == .subscription {
				self.receipt.refresh() { error in
					completion?(product, nil)
					self.state = .idle
					Notifications.didPurchaseProduct.post()
				}
			} else {
				completion?(product, nil)
				self.state = .idle
				Notifications.didPurchaseProduct.post()
			}
		}
	}
	
	func product(from id: Product.ID?) -> Product? {
		guard let id = id else { return nil }
		return self.availableProducts[id]
	}
	
	func productID(from string: String?) -> Product.ID? {
		return self.allProductIDs.filter({ $0.rawValue == string }).first
	}
}

extension CapitalistManager: SKPaymentTransactionObserver {
	public func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
		for transaction in transactions {
			switch transaction.transactionState {
			case .purchased, .restored:
				if let product = self.product(from: self.productID(from: transaction.payment.productIdentifier)) {
					self.recordPurchase(of: product)
					SKPaymentQueue.default().finishTransaction(transaction)
				}
				
			case .purchasing: print("Started purchase flow for \(transaction.payment.productIdentifier)")
			case .deferred: print("Purchased deferred for \(transaction.payment.productIdentifier)")
			case .failed:
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
		
		self.waitingPurchases.remove(prod.id)
		
		self.purchaseCompletion?(product, error)
		self.purchaseCompletion = nil

		if self.state == .purchasing(prod) {
			var userInfo = error != nil ? ["error": error!] : nil
			if let err = error as? SKError, err.code == .paymentCancelled || err.code == .paymentNotAllowed { userInfo = nil }
			NotificationCenter.default.post(name: Notifications.didFailToPurchaseProduct, object: prod, userInfo: userInfo)
			self.state = .idle
		}

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
			self.purchaseQueue.resume()
			
		case .purchasing(let product):
			self.failPurchase(of: product, dueTo: error)
			
		case .restoring: break
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
		
		self.receipt.updateCachedReciept()
		self.purchaseQueue.resume()
		Notifications.didFetchProducts.post()
	}
}

extension CapitalistManager {
	public enum CapitalistError: String, Error, LocalizedError, CustomStringConvertible {
		case productNotFound, purchaseAlreadyInProgress, requestTimedOut
		public var localizedDescription: String { return self.rawValue }
		public var description: String { return self.rawValue }
	}
	
	public enum State: Equatable { case idle, fetchingProducts, purchasing(Product), restoring
		public static func ==(lhs: State, rhs: State) -> Bool {
			switch (lhs, rhs) {
			case (.idle, .idle): return true
			case (.fetchingProducts, .fetchingProducts): return true
			case (.purchasing(let lhProd), .purchasing(let rhProd)): return lhProd == rhProd
			default: return false
			}
		}
	}
}


extension CapitalistManager {
	struct Notifications {
		static let didFetchProducts = Notification.Name("CapitalistManager.didFetchProducts")
		static let didRefreshReceipt = Notification.Name("CapitalistManager.didRefreshReceipt")

		static let startingProductPurchase = Notification.Name("CapitalistManager.startingProductPurchase")
		static let didPurchaseProduct = Notification.Name("CapitalistManager.didPurchaseProduct")
		static let didFailToPurchaseProduct = Notification.Name("CapitalistManager.didFailToPurchaseProduct")

		static let startingProductTrial = Notification.Name("CapitalistManager.startingProductTrial")
		static let didTrialProduct = Notification.Name("CapitalistManager.didTrialProduct")
		static let didFailToTrialProduct = Notification.Name("CapitalistManager.didFailToTrialProduct")
	}
}
