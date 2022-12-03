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
	
	@discardableResult
	public func purchase(_ id: Product.ID, completion: ((Product?, Error?) -> Void)? = nil) -> Bool {
		guard let product = self.product(for: id) else {
			completion?(nil, CapitalistError.productNotFound)
			
			NotificationCenter.default.post(name: Notifications.didFailToPurchaseProduct, object: id, userInfo: ["error": CapitalistError.productNotFound])
			delegate?.didFailToPurchase(productID: id, error: CapitalistError.productNotFound)
			return false
		}
		
		return purchase(product, completion: completion)
	}
	
	@discardableResult
	public func purchase(_ product: Product, completion: ((Product?, Error?) -> Void)? = nil) -> Bool {
		guard let skProduct = product.product else {
			completion?(nil, CapitalistError.productNotFound)
			
			NotificationCenter.default.post(name: Notifications.didFailToPurchaseProduct, object: product.id, userInfo: ["error": CapitalistError.productNotFound])
			delegate?.didFailToPurchase(productID: product.id, error: CapitalistError.productNotFound)

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
}
