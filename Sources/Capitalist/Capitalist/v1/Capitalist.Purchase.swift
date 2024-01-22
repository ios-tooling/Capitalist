//
//  File.swift
//  
//
//  Created by Ben Gottlieb on 12/2/22.
//

import Foundation
import StoreKit

extension Capitalist {
	func reportError(_ error: Error, for id: Product.Identifier) {
		DispatchQueue.main.async {
			NotificationCenter.default.post(name: Notifications.didFailToPurchaseProduct, object: id, userInfo: ["error": error])
			self.delegate?.didFailToPurchase(productID: id, error: error)
		}
	}
	
	public func purchase(_ id: Product.Identifier) async throws {
		guard let product = self[id] else { throw CapitalistError.productNotFound }
		try await purchase(product)
	}
	
	public func purchase(_ product: Product) async throws {
		guard let prod = product.product else { throw CapitalistError.productNotFound }
		let result = try await prod.purchase()
		print(result)
	}
}
