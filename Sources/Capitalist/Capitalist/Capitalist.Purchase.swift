//
//  File.swift
//  
//
//  Created by Ben Gottlieb on 12/2/22.
//

import Foundation
import StoreKit

extension Capitalist {
	public func purchase(_ id: Product.ID) async throws -> Product {		
		let product: Product = try await withCheckedThrowingContinuation { continuation in
			self.purchase(id) { product, error in
				if let product {
					continuation.resume(returning: product)
				} else if let error {
					continuation.resume(throwing: error)
				} else {
					continuation.resume(throwing: CapitalistError.unknownStoreKitError)
				}
			}
		}
		
		return product
	}
	
	func reportError(_ error: Error, for id: Product.ID) {
		DispatchQueue.main.async {
			NotificationCenter.default.post(name: Notifications.didFailToPurchaseProduct, object: id, userInfo: ["error": error])
			self.delegate?.didFailToPurchase(productID: id, error: error)
		}
	}
	
	@discardableResult
	public func purchase(_ id: Product.ID, completion: ((Product?, Error?) -> Void)? = nil) -> Bool {
		guard let product = self[id] else {
			completion?(nil, CapitalistError.productNotFound)
			reportError(CapitalistError.productNotFound, for: id)
			return false
		}
		
		return purchase(product, completion: completion)
	}
	
	@discardableResult
	public func purchase(_ product: Product, completion: ((Product?, Error?) -> Void)? = nil) -> Bool {
		if #available(iOS 15, macOS 12, *), useStoreKit2 {
			guard let prod = product.product2 as? StoreKit.Product else {
				completion?(nil, CapitalistError.storeKit2ProductNotFound)
				reportError(CapitalistError.storeKit2ProductNotFound, for: product.id)
				
				return false
			}
			
			Task {
				do {
					let result = try await prod.purchase(options: [])
					switch result {
					case .success(let verificationResult):
						switch verificationResult {
						case .unverified(_, let verificiationError):
							completion?(nil, CapitalistError.unverified)
							reportError(CapitalistError.unverified, for: product.id)
							print("Purchase was unverified for \(product), \(verificiationError)")
							completion?(nil, CapitalistError.unverified)
							
						case .verified(let transaction):
							print("Success! \(transaction)")
							self.recordPurchase(of: product, at: transaction.purchaseDate, expirationDate: transaction.expirationDate, restored: false)
							completion?(product, nil)
						}
						
					case .userCancelled:
						completion?(nil, CapitalistError.cancelled)
						reportError(CapitalistError.cancelled, for: product.id)
						print("User cancelled purchase of \(product)")
						completion?(nil, CapitalistError.cancelled)
					case .pending:
						completion?(nil, CapitalistError.purchasePending)
						reportError(CapitalistError.purchasePending, for: product.id)
						print("Purhcase is pending for \(product)")
						completion?(nil, CapitalistError.purchasePending)
					@unknown default:
						completion?(nil, CapitalistError.unknownStoreKitError)
						reportError(CapitalistError.unknownStoreKitError, for: product.id)
						print("Unknown storekit error for \(product)")
						completion?(nil, CapitalistError.unknownStoreKitError)
					}
				} catch {
					completion?(nil, error)
					reportError(error, for: product.id)
				}
			}
			return true
		}

		guard let skProduct = product.product else {
			completion?(nil, CapitalistError.storeKitProductNotFound)
			reportError(CapitalistError.storeKitProductNotFound, for: product.id)
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
				DispatchQueue.main.async {
					self.purchaseCompletion?(product, nil)
					NotificationCenter.default.post(name: Notifications.didPurchaseProduct, object: product, userInfo: Notification.purchaseFlagsDict(.prepurchased))
					self.delegate?.didPurchase(product: product, flags: .prepurchased)
					self.state = .idle
				}
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
}
