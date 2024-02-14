//
//  Capitalist.Product.swift
//

import Foundation
import StoreKit

// https://developer.apple.com/app-store/subscriptions/

extension Capitalist {
	public struct Product: CustomStringConvertible, Equatable, Identifiable {
		public struct Identifier: Equatable, Hashable, CustomStringConvertible, Identifiable {
			public let rawValue: String
			public let name: String?
			public var storeKitProduct: StoreKit.Product?
			public var description: String { return self.rawValue }
			public let isPrepurchased: Bool
			public let subscriptionDuration: SubscriptionDuration?
			public var id: String { rawValue }
			
			public static func ==(lhs: Self, rhs: Self) -> Bool {
				lhs.rawValue == rhs.rawValue
			}
			public func hash(into hasher: inout Hasher) {
				hasher.combine(rawValue)
			}
			
			var isValid: Bool { return !self.rawValue.isEmpty }
			
			static let none = Identifier(rawValue: "NO PRODUCT")
			
			public init(rawValue: String, name: String? = nil, isPrepurchased: Bool = false, subscriptionDuration: SubscriptionDuration? = nil) {
				self.rawValue = rawValue
				self.name = name
				self.isPrepurchased = isPrepurchased
				self.subscriptionDuration = subscriptionDuration
			}
		}
		
		public var info: [String: Any]?
		public var kind: StoreKit.Product.ProductType { product?.type ?? .consumable }
		public let id: Capitalist.Product.Identifier
		let storeKitProductID: String
		public var product: StoreKit.Product?
		public var recentPurchaseDate: Date? { didSet { updateSubscriptionInfo() }}
		public var recentTransactionID: String?
		var expirationDate: Date?
		var onDeviceExpirationDate: Date?
		public var name: String? {
			if let name = product?.displayName { return name }
			return id.name
		}

		
		public init?(product: StoreKit.Product, id localID: Identifier? = nil, info: [String: Any]? = nil) {
			guard let id = localID ?? product.id.capitalistProductID else { return nil }

			self.info = info
			self.id = id
			self.product = product
			storeKitProductID = product.id
		}

		public init?(storeKitProductID: String, id localID: Identifier? = nil, info: [String: Any]? = nil) {
			guard let capProd = Capitalist.instance[storeKitProductID] else { return nil }
			self.info = info
			self.id = capProd.id
			self.storeKitProductID = storeKitProductID
		}
		
		public var introductoryPrice: String? {
			product?.subscription?.introductoryOffer?.displayPrice
		}
		
		public var freeTrialDays: Int? {
			guard let count = product?.subscription?.introductoryOffer?.periodCount, let unit = product?.subscription?.introductoryOffer?.period.unit else { return nil }
			
			return switch unit {
			case .day: count
			case .week: count * 7
			case .month: count * 30
			case .year: count * 365
			@unknown default: nil
			}
		}
		
		public var freeTrialDurationDescription: String? { product?.subscription?.introductoryOffer?.period.localizedDuration }
		
		public var description: String {
			var text = self.id.rawValue + " - " + self.kind.rawValue
			if let reason = self.expirationReason { text += ", Expired: \(reason)" }
			if #available(iOS 11.2, OSX 10.13.2, *) {
				let hasUsedTrial = self.isInTrialPeriod || self.isInIntroOfferPeriod || self.originalPurchaseDate != nil
				if !hasUsedTrial, self.introductoryPrice != nil { text += " can trial" }
			}
			if self.isInTrialPeriod { text += " in trial" }
			if self.isInIntroOfferPeriod { text += " in intro period" }
			if self.isInBillingRetryPeriod { text += " is retrying billing" }
			if self.isSubscriptionActive, let date = self.subscriptionExpirationDate {
				text += " Active until \(date)"
			} else if let expired = self.subscriptionExpirationDate {
				text += " expired at \(expired)"
			}
			
			return text
		}
		
		func isOlderThan(receipt: [String: Any]) -> Bool {
			guard let receiptPurchaseDate = receipt.expirationDate else { return false }
			guard let purchaseDate = self.date(for: "expires_date") else { return true }
			
			return receiptPurchaseDate > purchaseDate
		}
				
		var isPurchaseable: Bool {
			product != nil
		}
		
		static let currencyFormatter: NumberFormatter = {
			let formatter = NumberFormatter()
			formatter.numberStyle = .currency
			return formatter
		}()
		
		mutating func updateSubscriptionInfo() {
			if let date = recentPurchaseDate, let expiration = self.id.subscriptionDuration?.expiration(startingAt: date) {
				onDeviceExpirationDate = expiration
			}
		}
		
		public var expirationReason: ExpirationReason? {
			guard let reason = info?["expiration_intent"] as? Int else { return nil }
			return ExpirationReason(rawValue: reason)
		}
		
		public var title: String? { product?.displayName }
		public var rawPrice: Double? {
			guard let raw = product?.price else { return nil }
			return Double(truncating: raw as NSNumber)
		}
		
		public var price: Decimal? { product?.price }

		public var localizedPrice: String? { product?.displayPrice }

		public var isInBillingRetryPeriod: Bool { return Bool(any: self.info?["is_in_billing_retry_period"]) }
		public var isInIntroOfferPeriod: Bool { return Bool(any: self.info?["is_in_intro_offer_period"]) }
		public var isInTrialPeriod: Bool { return Bool(any: self.info?["is_trial_period"]) }
		public var subscriptionCancellationDate: Date? {
			if let date = self.date(for: "cancellation_date") { return date }
			guard let recentPurchase = recentPurchaseDate, let duration = subscriptionDuration else { return nil }
			
			return recentPurchase.addingTimeInterval(duration)
		}
		public var subscriptionDuration: TimeInterval? { product?.subscription?.subscriptionPeriod.duration }
		public var subscriptionExpirationDate: Date? {
			if let expirationDate { return expirationDate }
			guard let onDevice = onDeviceExpirationDate else { return self.date(for: "expires_date") }
			guard let receipt = self.date(for: "expires_date") else { return onDevice }
			
			return max(onDevice, receipt)
		}
		public var originalPurchaseDate: Date? { return self.date(for: "original_purchase_date") }
		public var purchaseDate: Date? { return self.date(for: "purchase_date") }
		public var hasUsedTrial: Bool {
			get async { await product?.subscription?.isEligibleForIntroOffer == true }
		}
		public var isSubscriptionActive: Bool {
			guard let expirationDate = self.subscriptionExpirationDate else { return false }
			return expirationDate > Date()
		}
		public var expirationDateString: String {
			guard let date = subscriptionExpirationDate else { return "--" }
			return DateFormatter.buildPretty().string(from: date)
		}
		
		public var quantity: Int { return Int(any: self.info?["quantity"] ?? "") }
		public var hasPurchased: Bool {
			get async {
				guard let entitlement = try? await product?.currentEntitlement?.payloadValue else { return false }
				if let expiresAt = entitlement.expirationDate { return expiresAt > .now }
				return true
			}
		}
		
		func date(for key: String) -> Date? {
			guard let dateString = self.info?[key] as? String else { return nil }
			
			//dateString = dateString.replacingOccurrences(of: "Etc/GMT", with: "GMT")
			return dateString.toCapitalistDate()
		}
		
		public static func ==(lhs: Product, rhs: Product) -> Bool {
			return lhs.id == rhs.id
		}
		
		public var subscriptionState: Product.SubscriptionState {
			if let validUntil = self.subscriptionExpirationDate {
				if validUntil > Date() {
					if self.isInTrialPeriod { return .trial(validUntil) }
					return .valid(validUntil)
				}
				
				if Capitalist.instance.isPurchasing(products: [self.id]) { return .purchasing }
				return .expired(validUntil)
			}
			
			if Capitalist.instance.isPurchasing(products: [self.id]) { return .purchasing }
			return .none
		}
		
		public func fetchSubscriptionState(completion: @escaping (Product.SubscriptionState) -> Void) {
			let state = self.subscriptionState
			
			if state.isExpired {
				Capitalist.instance.receipt?.refresh() { error in completion(self.subscriptionState) }
			} else {
				completion(self.subscriptionState)
			}
		}
		
		public enum SubscriptionState: CustomStringConvertible { case none, purchasing, purchased, trial(Date), valid(Date), expired(Date), billingGracePeriod
			public var isValid: Bool {
				switch self {
				case .trial(_), .valid(_), .purchased, .billingGracePeriod: return true
				default: return false
				}
			}
			
			public var isExpired: Bool {
				switch self {
				case .billingGracePeriod, .expired(_): return true
				default: return false
				}
			}
			
			public var description: String {
				switch self {
				case .trial(let date): return "In trial until \(self.string(from: date))"
				case .expired(let date): return "Expired at \(self.string(from: date))"
				case .none: return "Not purchased"
				case .purchasing: return "Purchasing"
				case .purchased: return "Purchasing"
				case .billingGracePeriod: return "Retrying Billing"
				case .valid(let date): return "Valid until \(self.string(from: date))"
				}
			}
			
			func string(from date: Date) -> String {
				DateFormatter.buildPretty().string(from: date)
			}
		}
		
		public enum ExpirationReason: Int, CustomStringConvertible {
			case canceled = 1, billingError, rejectedPriceIncrease, unavailable, unknown
			public var description: String {
				switch self {
				case .canceled: return "Cancelled"
				case .billingError: return "Billing Error"
				case .rejectedPriceIncrease: return "Rejected Price Increase"
				case .unavailable: return "Unavailable"
				case .unknown: return "Unknown"
				}
			}
		}
	}
	
	public func purchasePhase(of product: Product.Identifier) -> ProductPurchsePhase {
		if product.isPrepurchased { return .prepurchased }
		if self.isPurchasing(product) { return .purchasing }
		if self.hasPurchased(product) { return .purchased }
		return .idle
	}
	
	public enum SubscriptionDuration { case oneWeek, twoWeeks, threeWeeks, oneMonth, twoMonths, threeMonths, sixMonths, oneYear
		func expiration(startingAt: Date) -> Date {
			var components = DateComponents()
			
			switch self {
			case .oneWeek: components.day = 7
			case .twoWeeks: components.day = 14
			case .threeWeeks: components.day = 21
			case .oneMonth: components.month = 1
			case .twoMonths: components.month = 2
			case .threeMonths: components.month = 3
			case .sixMonths: components.month = 6
			case .oneYear: components.year = 1
			}
			
			if let date = Calendar.current.date(byAdding: components, to: startingAt) {
				return date
			}
			
			return startingAt
		}
	}
	
}

extension DateFormatter {
	 static func buildPretty() -> DateFormatter {
		  let prettyFormatter = DateFormatter()
		  prettyFormatter.dateStyle = .short
		  prettyFormatter.timeStyle = .short

		  return prettyFormatter
	 }
	static let pretty = buildPretty()
}


extension String {
	static func capitalistFormatter() -> DateFormatter {
		let formatter = DateFormatter()
		formatter.dateFormat = "yyyy-MM-dd HH:mm:ss VV"
		
		return formatter
	}
	
	func toCapitalistDate() -> Date? {
		//formatter.dateFormat = "yyyy-MM-dd HH:mm:ss z"
					
		return String.capitalistFormatter().date(from: self)
	}
}

extension Dictionary where Key == String {
	var purchaseDate: Date? {
		guard let newString = self["purchase_date"] as? String, let newDate = newString.toCapitalistDate() else { return nil }
		
		return newDate
	}

	var expirationDate: Date? {
		guard let newString = self["expires_date"] as? String, let newDate = newString.toCapitalistDate() else { return nil }
		
		return newDate
	}
}

extension StoreKit.Product.SubscriptionPeriod {
	func expiration(startingAt: Date) -> Date {
		let subDuration = duration
		let newDate = startingAt.addingTimeInterval(subDuration)
		return newDate
	}
	
	var duration: TimeInterval {
		unit.timeInterval * TimeInterval(value)
	}
}

extension StoreKit.Product.SubscriptionPeriod.Unit {
	var timeInterval: TimeInterval {
		switch self {
		case .day: 1440 * 60
		case .week: 7 * 1440 * 60
		case .month: 31 * 1440 * 60
		case .year: 365 * 1440 * 60
		default: 0
		}
	}
}

fileprivate extension String {
	var capitalistProductID: Capitalist.Product.Identifier? {
		Capitalist.instance.productID(from: self)
	}
}

extension Array where Element == Capitalist.Product.Identifier {
	func contains(_ productID: String) -> Bool {
		return self.firstIndex(where: { $0.rawValue == productID }) != nil
	}
}
