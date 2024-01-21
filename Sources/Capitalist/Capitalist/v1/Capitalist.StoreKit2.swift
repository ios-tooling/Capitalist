//
//  File.swift
//  
//
//  Created by Ben Gottlieb on 12/30/22.
//

import Foundation
import StoreKit

@available(iOS 15.0, macOS 12, *)
extension Capitalist {
	func checkStoreKit2Transactions() {
		Task {
			for await result in Transaction.currentEntitlements {
				switch result {
				case .verified(let transaction):
					if let product = self[transaction.productID] {
						self.recordPurchase(of: product, at: transaction.purchaseDate, expirationDate: transaction.expirationDate, restored: false, transactionID: "\(transaction.id)", originalTransactionID: "\(transaction.originalID)")
					} else {
						print("Got a transaction for an unknown product: \(transaction)")
						let newProductID = Capitalist.Product.ID(rawValue: transaction.productID)
						if let newProduct = Capitalist.Product(storeKitProductID: transaction.productID, id: newProductID) {
							self.recordPurchase(of: newProduct, at: transaction.purchaseDate, expirationDate: transaction.expirationDate, restored: false, transactionID: "\(transaction.id)", originalTransactionID: "\(transaction.originalID)")
						}
					}
				case .unverified(let unverTransaction, let error):
					print("Got an unverified transaction from StoreKit: \(unverTransaction), \(error)")
				}
			}
		}
	}
	
	func startStoreKit2Listener() {
		Task.detached {
			for await result in Transaction.updates {
				switch result {
				case .verified(let transaction):
					self.recordPurchase(of: transaction.capitalistProduct, at: transaction.purchaseDate, expirationDate: transaction.expirationDate, restored: true, transactionID: "\(transaction.id)", originalTransactionID: "\(transaction.originalID)")
					await transaction.finish()

				case .unverified(let unverTransaction, let error):
					print("Got an unverified transaction from StoreKit: \(unverTransaction), \(error)")
					await unverTransaction.finish()
				}
			}
		}
	}
}

@available(iOS 15.0, macOS 12, *)
extension StoreKit.Transaction {
	var capitalistProduct: Capitalist.Product {
		if let id = Capitalist.instance.productID(from: productID) {
			if let product = Capitalist.instance[id] { return product }
			let product = Capitalist.Product(storeKitProductID: self.productID, id: id, info: nil)!

			Capitalist.instance.addAvailableProduct(product)
			return product
		}
		
		let id = Capitalist.Product.ID(rawValue: productID)
		let product = Capitalist.Product(storeKitProductID: productID, id: id, info: nil)!
		Capitalist.instance.addAvailableProduct(product)
		return product
	}
}
