//
//  ProductWatcher.swift
//  
//
//  Created by ben on 5/5/20.
//

import Foundation
import CrossPlatformKit

#if canImport(Cocoa)
	import Cocoa
#endif

#if canImport(UIKit)
	import UIKit
#endif

open class ProductWatcher: NSObject {
	public let productID: CapitalistManager.Product.ID
	public var product: CapitalistManager.Product? {
		CapitalistManager.instance.product(for: self.productID)
	}
	
	#if os(OSX)
		open var progressIndicator: NSProgressIndicator?
	#endif
	#if os(iOS)
		open var progressIndicator: UIActivityIndicatorView?
	#endif
	
	open var purchasedViews: [UXView] = []
	open var purchasingViews: [UXView] = []
	open var notPurchasedViews: [UXView] = []

	public init(productID: CapitalistManager.Product.ID) {
		self.productID = productID
		super.init()

		CapitalistManager.Notifications.didPurchaseProduct.watch(self, message: #selector(purchaseStateChanged))
		CapitalistManager.Notifications.didFailToPurchaseProduct.watch(self, message: #selector(purchaseStateChanged))
		CapitalistManager.Notifications.startingProductPurchase.watch(self, message: #selector(purchaseStateChanged))
	}
	
	open func addPurchasedView(_ view: UXView) { self.purchasedViews.append(view) }
	open func addPurchasingView(_ view: UXView) { self.purchasingViews.append(view) }
	open func addNotPurchasedView(_ view: UXView) { self.notPurchasedViews.append(view) }
	
	@objc func purchaseStateChanged() {
		self.updateControls()
	}
	
	open func updateControls() {
		switch CapitalistManager.instance.purchasePhase(of: self.productID) {
		case .prepurchased:
			self.purchasingViews.forEach { $0.isHidden = true }
			self.notPurchasedViews.forEach { $0.isHidden = true }
			self.purchasedViews.forEach { $0.isHidden = true }

		case .purchased:
			self.purchasingViews.forEach { $0.isHidden = true }
			self.notPurchasedViews.forEach { $0.isHidden = true }
			self.purchasedViews.forEach { $0.isHidden = false }

		case .purchasing:
			#if os(OSX)
				self.progressIndicator?.startAnimation(nil)
			#endif

			#if os(iOS)
				self.progressIndicator?.startAnimating()
			#endif

			self.purchasedViews.forEach { $0.isHidden = true }
			self.notPurchasedViews.forEach { $0.isHidden = true }
			self.purchasingViews.forEach { $0.isHidden = false }

		case .idle:
			self.purchasedViews.forEach { $0.isHidden = true }
			self.purchasingViews.forEach { $0.isHidden = true }
			self.notPurchasedViews.forEach { $0.isHidden = false }
		}
	}
}
