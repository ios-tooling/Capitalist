//
//  Capitalist+PaymentQueue.swift
//  
//
//  Created by Ben Gottlieb on 12/9/22.
//

import StoreKit

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
				if let product = self[transaction.payment.productIdentifier] {
					self.recordPurchase(of: product, at: transaction.transactionDate, expirationDate: nil, restored: transaction.transactionState == .restored, transactionID: transaction.transactionIdentifier, originalTransactionID: transaction.original?.transactionIdentifier)
				} else {
					if let newProduct = Capitalist.Product(product: nil, id: Product.ID(rawValue: transaction.payment.productIdentifier, kind: .notSet)) {
						self.addAvailableProduct(newProduct)
						self.recordPurchase(of: newProduct, at: transaction.transactionDate, expirationDate: nil, restored: transaction.transactionState == .restored, transactionID: transaction.transactionIdentifier, originalTransactionID: transaction.original?.transactionIdentifier)
					}
				}
				SKPaymentQueue.default().finishTransaction(transaction)

			case .purchasing: print("Started purchase flow for \(transaction.payment.productIdentifier)")
			case .deferred: print("Purchased deferred for \(transaction.payment.productIdentifier)")
			case .failed:
				self.failPurchase(of: self[transaction.payment.productIdentifier], dueTo: transaction.error)
				SKPaymentQueue.default().finishTransaction(transaction)
				
				
			@unknown default:
				self.failPurchase(of: self[transaction.payment.productIdentifier], dueTo: transaction.error)
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
		
		DispatchQueue.main.async {
			let completion = self.purchaseCompletion
			if let index = self.waitingPurchases.firstIndex(of: prod.id) {
				self.waitingPurchases.remove(at: index)
			}
			
			self.purchaseCompletion = nil
			
			if self.state == .purchasing(prod) {
				var userInfo: [String: Any]? = error != nil ? ["error": error!] : nil
				if let err = error as? SKError, err.code == .paymentCancelled || err.code == .paymentNotAllowed { userInfo = nil }
				self.state = .idle
				NotificationCenter.default.post(name: Notifications.didFailToPurchaseProduct, object: prod.id, userInfo: userInfo)
				
				if (error as? SKError)?.code == .paymentCancelled {
					self.delegate?.didFailToPurchase(productID: prod.id, error: CapitalistError.cancelled)
				} else {
					self.delegate?.didFailToPurchase(productID: prod.id, error: error ?? CapitalistError.unknownStoreKitError)
				}
			}
			
			completion?(product, error)
			print("Failed to purchase \(prod), \(error?.localizedDescription ?? "no error description").")
		}
	}
}
