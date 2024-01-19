//
//  Capitalist+Delegates.swift
//  
//
//  Created by Ben Gottlieb on 1/18/24.
//

import Foundation

public struct PurchaseDetails {
	public let flags: Capitalist.PurchaseFlag
	public let transactionID: String?
	public let originalTransactionID: String?
	public let expirationDate: Date?
}

public protocol CapitalistDelegate: AnyObject {
	func didFetchProducts()
	func didPurchase(product: Capitalist.Product, details: PurchaseDetails)
	func didFailToPurchase(productID: Capitalist.Product.ID, error: Error)
}

public protocol CapitalistReceiptDelegate: AnyObject {
	func didDecodeReceipt()
}
