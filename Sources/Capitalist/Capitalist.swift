//
//  Capitalist.swift
//

import Foundation
import StoreKit

/// Call Capitalist.instance.setup(with: Secret, productIDs: [Product IDs]) in AppDelegate.didFinishLaunching

public protocol CapitalistDelegate: AnyObject {
	func didFetchProducts()
	func didPurchase(product: Capitalist.Product, flags: Capitalist.PurchaseFlag)
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
	
	public var state = State.idle { didSet { self.purchaseTimeOutTimer?.invalidate() }}
	
	private weak var delegate: CapitalistDelegate?
	private var isSetup = false
	private var purchaseQueue = DispatchQueue(label: "purchasing")
	private var purchaseCompletion: ((Product?, Error?) -> Void)?
	private weak var purchaseTimeOutTimer: Timer?
	private var productsRequest: SKProductsRequest?
	
	public func setup(delegate: CapitalistDelegate, with secret: String? = nil, productIDs: [Product.ID], refreshReceipt: Bool = false, validatingReceiptWithServer: Bool = true) {
		if isSetup {
			print("Capitalist.setup() should only be called once.")
			return
		}
		
		isSetup = true
		self.delegate = delegate
		SKPaymentQueue.default().add(self)
		Capitalist.Receipt.appSpecificSharedSecret = secret
		allProductIDs = productIDs
		receipt = Receipt(validating: validatingReceiptWithServer)
		requestProducts()
		if refreshReceipt { checkForPurchases() }
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
			
			NotificationCenter.default.post(name: Notifications.didFailToPurchaseProduct, object: id, userInfo: ["error": CapitalistError.productNotFound])
			
			return false
		}
		
		guard self.state == .idle else {
			completion?(product, CapitalistError.purchaseAlreadyInProgress)
			return false
		}
		
		self.state = .purchasing(product)
		NotificationCenter.default.post(name: Notifications.startingProductPurchase, object: nil)
		
		self.purchaseCompletion = completion
		self.purchaseQueue.async {
			if product.id.kind == .nonConsumable, self.hasPurchased(product.id) {
				self.purchaseCompletion?(product, nil)
				NotificationCenter.default.post(name: Notifications.didPurchaseProduct, object: product, userInfo: Notification.purchaseFlagsDict(.prepurchased))
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
		if !purchasedProducts.contains(product.id) || product.id.kind == .consumable { self.purchasedProducts.append(product.id) }
		
		if let purchasedAt = date {
			switch product.id.kind {
			case .consumable:
				self.recordConsumablePurchase(of: product.id, at: purchasedAt)
				
			case .subscription:
				availableProducts[product.id]?.recentPurchaseDate = purchasedAt
				
			default: break
			}
		}
		
		if product.id.kind == .consumable, let purchasedAt = date {
			self.recordConsumablePurchase(of: product.id, at: purchasedAt)
		}
		
		let completion = self.purchaseCompletion
		let purchased = availableProducts[product.id] ?? product
		self.purchaseCompletion = nil
		
		self.receipt.loadBundleReceipt { error in
			if let err = error { print("Error when loading local receipt: \(err)") }
			completion?(purchased, nil)
			self.state = .idle
			NotificationCenter.default.post(name: Notifications.didPurchaseProduct, object: purchased, userInfo: Notification.purchaseFlagsDict(restored ? .restored : []))
			self.delegate?.didPurchase(product: purchased, flags: restored ? .restored : [])
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

extension Capitalist: SKPaymentTransactionObserver {
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
	
	public func paymentQueue(_ queue: SKPaymentQueue, shouldAddStorePayment payment: SKPayment, for product: SKProduct) -> Bool {
		true
	}
	
	
	
	func failPurchase(of product: Product?, dueTo error: Error?) {
		guard let prod = product else {
			self.purchaseCompletion = nil
			return
		}
		
		let completion = self.purchaseCompletion
		if let index = waitingPurchases.firstIndex(of: prod.id) {
			waitingPurchases.remove(at: index)
		}
		
		self.purchaseCompletion = nil
		
		if self.state == .purchasing(prod) {
			var userInfo: [String: Any]? = error != nil ? ["error": error!] : nil
			if let err = error as? SKError, err.code == .paymentCancelled || err.code == .paymentNotAllowed { userInfo = nil }
			self.state = .idle
			NotificationCenter.default.post(name: Notifications.didFailToPurchaseProduct, object: prod, userInfo: userInfo)
		}
		
		completion?(product, error)
		print("Failed to purchase \(prod), \(error?.localizedDescription ?? "no error description").")
	}
}

extension Capitalist: SKRequestDelegate {
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

extension Capitalist: SKProductsRequestDelegate {
	func requestProducts(productIDs: [Product.ID]? = nil ) {
		if self.state != .idle { return }
		
		self.state = .fetchingProducts
		self.purchaseQueue.suspend()
		let products = productIDs ?? self.allProductIDs
		self.productsRequest = SKProductsRequest(productIdentifiers: Set(products.map({ $0.rawValue })))
		productsRequest?.delegate = self
		productsRequest?.start()
	}
	
	public func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
		self.availableProducts = [:]
		response.products.forEach {
			if let prod = self.productID(from: $0.productIdentifier) {
				self.availableProducts[prod] = Product(product: $0)
			}
		}
		
		self.state = .idle
		
		self.receipt.updateCachedReceipt(label: "Product Request Completed")
		self.purchaseQueue.resume()
		NotificationCenter.default.post(name: Notifications.didFetchProducts, object: nil)
		self.delegate?.didFetchProducts()
		DispatchQueue.main.async { self.objectChanged() }
	}
	
	public func logCurrentProducts(label: String) {
		var text = label + "\n"
		
		for id in purchasedProducts {
			guard let product = self.product(for: id) else { continue }
			
			switch id.kind {
			case .subscription: text += "\(product) valid until: \(product.expirationDateString)\n"
			case .consumable: text += "\(product)\n"
			case .nonConsumable: text += "\(product)\n"
			case .none: text += "Bad product: \(product)\n"
			}
		}
		
		print("-------------------------------\n" + text + "-------------------------------")
	}
}

extension SKPaymentTransaction {
	var detailedDescription: String {
		var text = "\(self.payment.productIdentifier) - \(self.transactionState.description)"
		
		if let date = self.transactionDate {
			text += " at \(date.description)"
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

extension Capitalist {
	public enum Distribution { case development, testflight, appStore }
	
	public static var distribution: Distribution {
		#if DEBUG
			return .development
		#else
			#if os(OSX)
				let bundlePath = Bundle.main.bundleURL
				let receiptURL = bundlePath.appendingPathComponent("Contents").appendingPathComponent("_MASReceipt").appendingPathComponent("receipt")
				
				return FileManager.default.fileExists(at: receiptURL) ? .appStore : .development
			#endif
			#if targetEnvironment(simulator)
				return .development
			#else
				if Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" && MobileProvisionFile.default?.properties["ProvisionedDevices"] == nil { return .testflight }
			
				return .appStore
			#endif
		#endif
	}
}


fileprivate class MobileProvisionFile {
	fileprivate convenience init?(url: URL?) { self.init(data: url == nil ? nil : try? Data(contentsOf: url!)) }
	
	fileprivate var properties: NSDictionary!
	
	fileprivate static var `default`: MobileProvisionFile? = MobileProvisionFile(url: Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"))
	fileprivate init?(data: Data?) {
		guard let data = data else { return nil }
		
		guard let file = String(data: data, encoding: .ascii) else { return nil }
		let scanner = Scanner(string: file)
		if scanner.scanStringUpTo(string: "<?xml version=\"1.0\" encoding=\"UTF-8\"?>") != nil, let contents = scanner.scanStringUpTo(string: "</plist>") {
			let raw = contents.appending("</plist>")
			self.properties = raw.propertyList() as? NSDictionary
		}
		
		if self.properties == nil { return nil }
	}
}


fileprivate extension Scanner {
	 func scanStringUpTo(string: String) -> String? {
		if #available(iOS 13.0, iOSApplicationExtension 13.0, watchOS 6.0, OSX 10.15, OSXApplicationExtension 10.15, *) {
				return self.scanString(string)
		  } else {
				var result: NSString?
				self.scanUpTo(string, into: &result)
				return result as String?
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
					objectWillChange.send()
			  }
		 }
	}
#else
extension Capitalist {
	func objectChanged() { }
}
#endif
