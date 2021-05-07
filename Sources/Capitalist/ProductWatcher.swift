//
//  ProductWatcher.swift
//  
//
//  Created by ben on 5/5/20.
//

import Foundation

#if canImport(Cocoa)
	import Cocoa
    public typealias CapitalistView = NSView
#endif

#if canImport(UIKit)
	import UIKit
    public typealias CapitalistView = UIView
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
	
	open var purchasedViews: [CapitalistView] = []
	open var purchasingViews: [CapitalistView] = []
	open var notPurchasedViews: [CapitalistView] = []

	public init(productID: CapitalistManager.Product.ID) {
		self.productID = productID
		super.init()

        NotificationCenter.default.addObserver(self, selector: #selector(purchaseStateChanged), name: CapitalistManager.Notifications.didPurchaseProduct, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(purchaseStateChanged), name: CapitalistManager.Notifications.didFailToPurchaseProduct, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(purchaseStateChanged), name: CapitalistManager.Notifications.startingProductPurchase, object: nil)
	}
	
	open func addPurchasedView(_ view: CapitalistView) { self.purchasedViews.append(view) }
	open func addPurchasingView(_ view: CapitalistView) { self.purchasingViews.append(view) }
	open func addNotPurchasedView(_ view: CapitalistView) { self.notPurchasedViews.append(view) }
	
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
