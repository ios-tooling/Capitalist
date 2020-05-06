//
//  File.swift
//  
//
//  Created by ben on 5/6/20.
//

import Foundation

extension CapitalistManager {
	func recordConsumablePurchase(of id: Product.ID, at date: Date) {
		let purchase = ConsumablePurchase(productID: id, date: date)
		if !self.purchasedConsumables.contains(purchase) { self.purchasedConsumables.append(purchase) }
	}
	
	public struct ConsumablePurchase: Equatable {
		public let productID: Product.ID
		public let date: Date
		
		public static func ==(lhs: ConsumablePurchase, rhs: ConsumablePurchase) -> Bool {
			return lhs.productID == rhs.productID && lhs.date == rhs.date
		}
	}
}
