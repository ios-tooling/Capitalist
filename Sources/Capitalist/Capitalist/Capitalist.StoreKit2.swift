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
						self.recordPurchase(of: product, at: transaction.purchaseDate, expirationDate: transaction.expirationDate, restored: false)
					} else {
						print("Got a transaction for an unknown product: \(transaction)")
						let newProductID = Capitalist.Product.ID(rawValue: transaction.productID, kind: transaction.productType.capitalistType)
						if let newProduct = Capitalist.Product(product: nil, id: newProductID) {
							self.recordPurchase(of: newProduct, at: transaction.purchaseDate, expirationDate: transaction.expirationDate, restored: false)
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
					if let productID = self.productID(from: transaction.productID), let product = self[productID] {
						self.recordPurchase(of: product, at: transaction.purchaseDate, expirationDate: transaction.expirationDate, restored: true)
					} else {
						print("Got a transaction for an unknown product: \(transaction)")
					}
				case .unverified(let unverTransaction, let error):
					print("Got an unverified transaction from StoreKit: \(unverTransaction), \(error)")
				}
			}
		}
	}
}


@available(iOS 15.0, macOS 12, *)
extension StoreKit.Product.ProductType {
	var capitalistType: Capitalist.Product.ID.Kind {
		switch self {
		case .autoRenewable: return .subscription
		case .consumable: return .consumable
		case .nonConsumable: return .nonConsumable
		case .nonRenewable: return .subscription
		default: return .nonConsumable
		}
	}
}
