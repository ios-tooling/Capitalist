//
//  CapitalistManager.Receipt.swift
//

import Foundation
import StoreKit
import Studio

extension CapitalistManager {	
	public func currentExpirationDate(for productIDs: [Product.ID] = CapitalistManager.instance.allProductIDs) -> Date? {
		var newest: Date?

		for id in productIDs {
			guard let product = self.availableProducts[id], let date = product.subscriptionExpirationDate else { continue }

			if newest == nil || newest! < date { newest = date }
		}

		return newest
	}
	
	public func isInTrial(for productIDs: [Product.ID]) -> Bool {
		return self.availableProducts.values.filter({ productIDs.contains($0.id) && $0.isInTrialPeriod }).count > 0
	}
	
	public func hasUsedTrial(for productIDs: [Product.ID]) -> Bool {
		return self.availableProducts.values.filter({ productIDs.contains($0.id) && $0.hasUsedTrial }).count > 0
	}
	
	private func load(receipts: [[String: Any]]) {
		for receipt in receipts {
			guard
				let id = self.productID(from: receipt["product_id"] as? String ?? ""),
				let product = CapitalistManager.instance.product(for: id)
			else { continue }
			
			if product.isOlderThan(receipt: receipt) {
				self.availableProducts[id]?.info = receipt
				if self.availableProducts[id]?.id.kind == .nonConsumable, self.availableProducts[id]?.hasPurchased == true {
					self.purchasedProducts.append(id)
				}
			}
		}
	}
	
	public class Receipt: NSObject {
		public static var appSpecificSharedSecret: String!			//this should be found in AppStoreConnect
		public var isRefreshing = false
		public var cachedReciept: [String: Any]?
		var currentCheckingHash: Int?
		
		public override init() {
			super.init()
			
			DispatchQueue.main.async {
				self.loadLocal(refreshingIfRequired: false)
			}
		}
				
		var refreshCompletions: [(Error?) -> Void] = []
		
		public func refresh(completion: ((Error?) -> Void)? = nil) {
			if let comp = completion { self.refreshCompletions.append(comp) }
			
			if self.isRefreshing { return }
			let op = SKReceiptRefreshRequest(receiptProperties: nil)
			self.isRefreshing = true

			op.delegate = self
			op.start()
		}
		
		func updateCachedReciept() {
			if let recp = self.cachedReciept?["receipt"] as? [String: Any], let inApp = recp["in_app"] as? [[String: Any]] { CapitalistManager.instance.load(receipts: inApp) }
			if let info = self.cachedReciept?["latest_receipt_info"] as? [[String: Any]] { CapitalistManager.instance.load(receipts: info) }
		}
		
		func loadLocal(refreshingIfRequired: Bool = true, completion: ((Error?) -> Void)? = nil) {
			if let url = Bundle.main.appStoreReceiptURL, let receipt = try? Data(contentsOf: url) {
				self.isRefreshing = true
				self.validate(data: receipt) { receipt in
					self.cachedReciept = receipt
					self.isRefreshing = false
					self.updateCachedReciept()
					DispatchQueue.main.async {
						Notifications.didRefreshReceipt.notify()
						completion?(nil)
					}
				}
			} else if refreshingIfRequired {
				self.refresh(completion: completion)
			} else {
				completion?(nil)
			}
		}
		
		var validationCompletions: [ReceiptCompletion] = []
		
		func validate(data receiptData: Data, completion: @escaping ReceiptCompletion) {
			self.validationCompletions.append(completion)

			let hash = receiptData.hashValue
			if self.currentCheckingHash == hash {
				self.callValidationCompletions(with: self.cachedReciept)
				return
			}
			
			self.currentCheckingHash = hash
			let dict: [String: Any] = ["receipt-data": receiptData.base64EncodedString(), "password": Receipt.appSpecificSharedSecret ?? "", "exclude-old-transactions": true]
			let url = URL(string: "https://\(CapitalistManager.instance.useSandbox ? "sandbox" : "buy").itunes.apple.com/verifyReceipt")!
			var request = URLRequest(url: url)
			request.httpBody = try! JSONSerialization.data(withJSONObject: dict, options: [])
			request.httpMethod = "POST"
			
			let task = URLSession.shared.dataTask(with: request) { result, response, error in
				if let err = error { print("Error when validating receipt: \(err)") }
				if let data = result, let info = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any], let status = info["status"] as? Int {
					if status == 21007, !CapitalistManager.instance.useSandbox { // if the server sends back a 21007, we're in the Sandbox. Happens during AppReview
						CapitalistManager.instance.useSandbox = true
						self.currentCheckingHash = nil
						self.validate(data: receiptData, completion: completion)
						return
					} else if status == 21004 {
						print("Your secret (\(Receipt.appSpecificSharedSecret ?? "<missing>")) doesn't seem to be correct.")
						self.callValidationCompletions(with: nil)
					} else if status != 0 {
						print("Bad status (\(status)) returned from the AppStore.")
						self.callValidationCompletions(with: nil)
					} else {
						self.callValidationCompletions(with: info)
					}
				} else {
					self.callValidationCompletions(with: nil)
				}
			}
			
			task.resume()
		}
		
		func callValidationCompletions(with results: [String: Any]?) {
			let completions = self.validationCompletions
			self.currentCheckingHash = nil
			self.validationCompletions = []
			
			DispatchQueue.main.async {
				completions.forEach { $0(results) }
			}
		}
	}
}

extension CapitalistManager.Receipt: SKRequestDelegate {
	public func requestDidFinish(_ request: SKRequest) {
		self.isRefreshing = false
		self.loadLocal(refreshingIfRequired: false) { _ in
			self.callRefreshCompletions(with: nil)
		}
	}
	
	public func request(_ request: SKRequest, didFailWithError error: Error) {
		self.isRefreshing = false
		self.callRefreshCompletions(with: error)
		if request is SKReceiptRefreshRequest, (error as NSError).code == 100 {
			print("***** Make sure your test user is from the correct AppStoreConnect account. *****")
		} else {
			print("Error when loading \(request): \(error.localizedDescription)")
		}
	}
	
	func callRefreshCompletions(with error: Error?) {
		let comps = self.refreshCompletions
		self.refreshCompletions = []
		DispatchQueue.main.async {
			comps.forEach { $0(error) }
		}
	}
}

extension Array where Element == CapitalistManager.Product.ID {
	func contains(_ productID: String) -> Bool {
		return self.firstIndex(where: { $0.rawValue == productID }) != nil
	}
}

extension Bool {
	init(any: Any?) {
		if let bool = any as? Bool { self = bool }
		else if let str = any as? String, str == "true" { self = true }
		else { self = false }
	}
}


extension Int {
	init(any: Any?) {
		if let int = any as? Int { self = int }
		else if let str = any as? String, let int = Int(str) { self = int }
		else if let dbl = any as? Double { self = Int(dbl) }
		else { self = 0 }
	}
}

