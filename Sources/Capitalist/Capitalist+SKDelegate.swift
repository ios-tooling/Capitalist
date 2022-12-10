//
//  Capitalist+SKDelegate.swift
//  
//
//  Created by Ben Gottlieb on 12/9/22.
//

import StoreKit

extension Capitalist: SKRequestDelegate {
	public func requestDidFinish(_ request: SKRequest) {
		switch self.state {
		case .restoring:
			self.state = .idle
			
		default: break
		}
	}
	
	public func request(_ request: SKRequest, didFailWithError error: Error) {
		self.reportedError = error
		
		switch self.state {
		case .idle:
			print("We shouldn't hit an error when we're idle.")
			
		case .fetchingProducts: break
			
		case .purchasing(let product):
			print("Failed to purchase \(product): \(error)")
			self.failPurchase(of: product, dueTo: error)
			
		case .restoring:
			print("Restore failed: \(error)")
		}
		
		self.state = .idle
		print("Error from \(request): \(error)")
	}
	
	func load(products: [SKProduct]) {
		products.forEach {
			if let prod = self.productID(from: $0.productIdentifier) {
				self.availableProducts[prod] = Product(product: $0)
			}
		}
	}
}

extension Capitalist {
	func requestProducts(productIDs: [Product.ID]? = nil) {
		if self.state != .idle {
			if let ids = productIDs, Set(ids) != Set(allProductIDs) {
				pendingProducts = ids
			}
			return
		}
		
		self.state = .fetchingProducts
		self.purchaseQueue.suspend()
		let products = productIDs ?? self.allProductIDs
		allProductIDs = products
		
		productsRequest = ProductFetcher(ids: products) { result in
			switch result {
			case .failure(let err):
				self.productFetchError = err
				print("Failed to fetch products: \(err)")
				
			case .success:
				self.state = .idle
				
				self.receipt.updateCachedReceipt(label: "Product Request Completed")
				NotificationCenter.default.post(name: Notifications.didFetchProducts, object: nil)
				self.delegate?.didFetchProducts()
				DispatchQueue.main.async { self.objectChanged() }
			}
			self.productsRequest = nil
			if let next = self.pendingProducts {
				self.pendingProducts = nil
				self.requestProducts(productIDs: next)
			}
		}
		DispatchQueue.main.async { self.purchaseQueue.resume() }
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
			case .notSet: text += "Not set: \(product)"
			}
		}
		
		print("-------------------------------\n" + text + "-------------------------------")
	}
}

