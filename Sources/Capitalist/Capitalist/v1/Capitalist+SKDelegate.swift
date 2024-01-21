//
//  Capitalist+SKDelegate.swift
//  
//
//  Created by Ben Gottlieb on 12/9/22.
//

import StoreKit

extension Capitalist {
	func load(products: [StoreKit.Product]) {
		objectWillChange.send()
		products.forEach {
			if let prod = self.productID(from: $0.id) {
				self.addAvailableProduct(Product(product: $0, id: prod))
			}
		}
	}
	
	func load(products: [Product]) {
		objectWillChange.send()
		products.forEach { product in
			self.addAvailableProduct(product)
		}
	}
}

extension Capitalist {
	func requestProducts(productIDs: [Product.ID]? = nil) async throws {
		let products = productIDs ?? self.allProductIDs
		if products.isEmpty { return }
		self.state = .fetchingProducts

		self.purchaseQueue.suspend()
		
		let result = try await StoreKit.Product.products(for: products.map { $0.rawValue })
		for product in result {
			addAvailableProduct(Product(product: product, id: .init(rawValue: product.id)))
		}

		if self.state != .idle {
			if let ids = productIDs, Set(ids) != Set(allProductIDs) {
				pendingProducts = ids
			}
			return
		}
		DispatchQueue.main.async { self.purchaseQueue.resume() }
	}
	
	internal func logCurrentProducts(label: String) {
		var text = label + "\n"
		
		for id in purchasedProducts {
			guard let product = self[id] else { continue }
			
			switch product.kind {
			case .autoRenewable: text += "\(product) valid until: \(product.expirationDateString)\n"
			case .consumable: text += "\(product)\n"
			case .nonConsumable: text += "\(product)\n"
			default: text += "Not set: \(product)"
			}
		}
		
		print("-------------------------------\n" + text + "-------------------------------")
	}
}

