//
//  Capitalist.Notifications.swift
//  
//
//  Created by ben on 5/5/20.
//

import Foundation



extension Capitalist {
	public struct Notifications {
		public static let didFetchProducts = Notification.Name("Capitalist.didFetchProducts")
		public static let didRefreshReceipt = Notification.Name("Capitalist.didRefreshReceipt")

		public static let startingProductPurchase = Notification.Name("Capitalist.startingProductPurchase")
		public static let didPurchaseProduct = Notification.Name("Capitalist.didPurchaseProduct")
		public static let didFailToPurchaseProduct = Notification.Name("Capitalist.didFailToPurchaseProduct")

		public static let startingProductTrial = Notification.Name("Capitalist.startingProductTrial")
		public static let didTrialProduct = Notification.Name("Capitalist.didTrialProduct")
		public static let didFailToTrialProduct = Notification.Name("Capitalist.didFailToTrialProduct")
	}
}
