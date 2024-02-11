//
//  Capitalist.swift
//

import Foundation
import StoreKit

/// Call Capitalist.instance.setup(with: Secret, productIDs: [Product IDs]) in AppDelegate.didFinishLaunching

public class Capitalist: ObservableObject {
	public static let instance = Capitalist()
	private init() {  }
	
	public var state = State.idle { didSet { self.purchaseTimeOutTimer?.invalidate() }}
	public var purchasedProducts: [Product.Identifier] = []
	public var availableProducts: [Product.Identifier: Product] = [:]
	public var waitingPurchases: [Product.Identifier] = []
	public var useSandbox = (Capitalist.distribution != .appStore && Capitalist.distribution != .testflight)
	public var allProductIDs: [Product.Identifier] = []
	public var availableProductIDs: [Product.Identifier] { Array(availableProducts.keys) }
	public var purchaseTimeOut: TimeInterval = 120
	public var purchasedConsumables: [ConsumablePurchase] = []
	public var loggingOn = false
	public var subscriptionManagementURL = URL(string: "https://finance-app.itunes.apple.com/account/subscriptions")!
	public var reportedError: Error? { didSet { self.objectWillChange.send() }}
	public var receiptOverride: ReceiptOverride?
	public var isLoadingProducts = true

	internal var hasSales = false
	internal var storeExpirationDatesInDefaults = false
	internal var receipt: Receipt?

	
	weak var delegate: CapitalistDelegate?
	private var isSetup = false
	internal var purchaseQueue = DispatchQueue(label: "purchasing")
	internal let processingQueue = DispatchQueue(label: "capitalistProcessingQueue")
	internal var purchaseCompletion: ((Product?, Error?) -> Void)?
	internal weak var purchaseTimeOutTimer: Timer?
	internal var pendingProducts: [Product.Identifier]?
	
	internal var currentReceiptData: Data? { receipt?.receiptData }
	
	public func setup(delegate: CapitalistDelegate? = nil, with secret: String? = nil, refreshReceipt: Bool = false, receiptOverride: ReceiptOverride? = nil) {
		if isSetup {
			print("Capitalist.setup() should only be called once.")
			return
		}
		
		startStoreKit2Listener()
		loadReceipt(secret: secret)
		
		if let over = receiptOverride { self.receiptOverride = over }
		isSetup = true
		self.delegate = delegate
	}
	
	public func loadReceipt(secret: String?) {
		Receipt.appSpecificSharedSecret = secret
		if receipt == nil { receipt = Receipt() }
		receipt?.loadBundleReceipt()
	}
	
	public func set(productIDs: [Product.Identifier]) async throws {
		try await load(productIDs: productIDs)

		await fetchCurrentEntitlements()
		allProductIDs = productIDs
		isLoadingProducts = false
		update()
		await MainActor.run { self.objectWillChange.send() }
	}
	
	public var originalPurchaseDate: Date? { receipt?.originalPurchaseDate }
	
	public func load(productIDs: [Product.Identifier]) async throws {
		let products = try await StoreKit.Product.products(for: productIDs.map { $0.id })
		for product in products {
			let prodID = builtProductID(from: product.id)
			var existing = self.availableProducts[prodID] ?? .init(product: product, id: prodID)
			existing?.product = product
			self.availableProducts[prodID] = existing
		}
	}
	
	public func fetchCurrentEntitlements() async {
		for await result in Transaction.currentEntitlements {
			handle(transaction: result)
		}
	}
	
	func handle(transaction: VerificationResult<Transaction>) {
		if case .verified(let trans) = transaction {
			let prodID = builtProductID(from: trans.productID)
			switch trans.productType {
			case .nonConsumable:
				purchasedProducts.append(prodID)
				
			case .autoRenewable:
				availableProducts[prodID]?.expirationDate = trans.expirationDate
				
			default: break
			}
			print("Fetched info for \(prodID): \(trans)")
		}
	}
	
	public func update(productIDs: [Product.Identifier]? = nil) {
		if let productIDs, Set(productIDs) == Set(allProductIDs) { return }
		
		Task {
			do {
				try await requestProducts(productIDs: productIDs)
			} catch {
				print("Failed to fetch products: \(error)")
			}
		}
	}
	
	public func checkForPurchases() {
		self.receipt?.refresh()
	}
	
	@available(iOS 14.0, *)
	public func presentCodeRedemptionSheet() {
		#if os(iOS)
		SKPaymentQueue.default().presentCodeRedemptionSheet()
		#endif
	}
	
	public func hasPurchased(_ product: Product.Identifier) -> Bool {
		return self.purchasedProducts.contains(product)
	}
	
	func isPurchasing(_ product: Product.Identifier? = nil, products: [Product.Identifier]? = nil) -> Bool {
		if let prod = product {
			return self.waitingPurchases.contains(prod)
		} else {
			let productIDs = products ?? (allProductIDs + availableProductIDs)
			for prod in productIDs { if self.waitingPurchases.contains(prod) { return true } }
		}
		return false
	}
	
	public func subscriptionState(of products: [Product.Identifier]? = nil) async -> Product.SubscriptionState {
		let productIDs = products ?? availableProductIDs
		
		if let validUntil = await currentExpirationDate(for: productIDs) {
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
			self.receipt?.refresh()
		} else {
			SKPaymentQueue.default().restoreCompletedTransactions()
		}
	}
	
	public subscript(id: Product.Identifier?) -> Product? {
		guard let id else { return nil }
		return availableProducts[id]
	}
	
	public subscript(string: String?) -> Product? {
		guard let id = productID(from: string) else { return nil }
		return self[id]
	}
	
	public func productID(from string: String?) -> Product.Identifier? {
		return (availableProductIDs + allProductIDs).filter({ $0.rawValue == string }).first
	}
	
	public func builtProductID(from string: String) -> Product.Identifier {
		(availableProductIDs + allProductIDs).filter({ $0.rawValue == string }).first ?? .init(rawValue: string)
	}
	
	func addAvailableProduct(_ product: Capitalist.Product?) {
		guard let product else { return }
		
		processingQueue.sync { self._addAvailableProduct(product) }
	}
	
	func _addAvailableProduct(_ product: Capitalist.Product) {
		let id = product.id
		if !allProductIDs.contains(id) { allProductIDs.append(id) }
		if var current = availableProducts[id] {
			current.info = product.info ?? current.info
			current.product = product.product ?? current.product
			current.recentPurchaseDate = product.recentPurchaseDate ?? current.recentPurchaseDate
			current.recentTransactionID = product.recentTransactionID ?? current.recentTransactionID
			current.expirationDate = product.expirationDate ?? current.expirationDate
			current.onDeviceExpirationDate = product.onDeviceExpirationDate ?? current.onDeviceExpirationDate
			
			availableProducts[id] = current
		} else {
			availableProducts[id] = product
		}
	}
	
	public func isProductAvailable(_ id: Product.Identifier) -> Bool { availableProducts[id]?.product != nil }
	
	public func canPurchase(_ id: Product.Identifier) async -> Bool {
		if self.state != .idle, self.state != .restoring { return false }
		guard !id.isPrepurchased, let product = self[id], product.isPurchaseable else { return false }
		
		return switch product.kind {
		case .consumable: true
		case .nonConsumable: !self.hasPurchased(id)
		case .autoRenewable: await currentExpirationDate(for: [id]) == nil
		default: false
		}
	}
	
	func recordPurchase(of product: Product, at date: Date?, expirationDate: Date?, restored: Bool, transactionID: String?, originalTransactionID: String?) {
		guard let receipt else {
			print("Receipt is not yet configured, did you call Capitalist.setup() first?")
			return
		}
		if !purchasedProducts.contains(product.id) || product.kind == .consumable { self.purchasedProducts.append(product.id) }
		
		if let purchasedAt = date {
			switch product.kind {
			case .consumable:
				self.recordConsumablePurchase(of: product.id, at: purchasedAt)
				
			case .autoRenewable:
				availableProducts[product.id]?.recentPurchaseDate = purchasedAt
				availableProducts[product.id]?.expirationDate = expirationDate
				availableProducts[product.id]?.recentTransactionID = transactionID
			default: break
			}
		}
		
		if product.kind == .consumable, let purchasedAt = date {
			self.recordConsumablePurchase(of: product.id, at: purchasedAt)
		}
		
		let completion = self.purchaseCompletion
		let purchased = availableProducts[product.id] ?? product
		availableProducts[product.id]?.recentTransactionID = transactionID
		self.purchaseCompletion = nil
		
		receipt.loadBundleReceipt { error in
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
					if receipt.receiptDecodeFailed {
						self.saveLocalExpirationDate(for: purchased)
					} else {
						self.clearLocalExpirationDate(for: purchased)
					}
				#endif
			}
			DispatchQueue.main.async {
				completion?(purchased, nil)
				self.delegate?.didPurchase(product: purchased, details: PurchaseDetails(flags: restored ? .restored : [], transactionID: transactionID, originalTransactionID: originalTransactionID, expirationDate: expirationDate))
				self.objectWillChange.send()
			}
		}
	}
}
