//
//  CapitalistManager.Notifications.swift
//  
//
//  Created by ben on 5/5/20.
//

import Foundation



extension CapitalistManager {
	public struct Notifications {
		public static let didFetchProducts = Notification.Name("CapitalistManager.didFetchProducts")
		public static let didRefreshReceipt = Notification.Name("CapitalistManager.didRefreshReceipt")

		public static let startingProductPurchase = Notification.Name("CapitalistManager.startingProductPurchase")
		public static let didPurchaseProduct = Notification.Name("CapitalistManager.didPurchaseProduct")
		public static let didFailToPurchaseProduct = Notification.Name("CapitalistManager.didFailToPurchaseProduct")

		public static let startingProductTrial = Notification.Name("CapitalistManager.startingProductTrial")
		public static let didTrialProduct = Notification.Name("CapitalistManager.didTrialProduct")
		public static let didFailToTrialProduct = Notification.Name("CapitalistManager.didFailToTrialProduct")
	}
}
