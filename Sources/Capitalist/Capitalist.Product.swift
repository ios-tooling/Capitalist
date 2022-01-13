//
//  Capitalist.Product.swift
//

import Foundation
import StoreKit

// https://developer.apple.com/app-store/subscriptions/ 

extension Capitalist {
	public func purchasePhase(of product: Product.ID) -> ProductPurchsePhase {
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
			
			return Calendar.current.date(byAdding: components, to: startingAt) ?? startingAt
		}
	}
	public struct Product: CustomStringConvertible, Equatable {
		public struct ID: Equatable, Hashable, CustomStringConvertible {
			public enum Kind: String { case none, nonConsumable, consumable, subscription, notSet }
			
			public let rawValue: String
			public let kind: Kind
			public var description: String { return self.rawValue }
			public let isPrepurchased: Bool
			public let subscriptionDuration: SubscriptionDuration?

			var isValid: Bool { return !self.rawValue.isEmpty }
			
			static let none = ID(rawValue: "", kind: .none)
			
			public init(rawValue: String, kind: Kind, isPrepurchased: Bool = false, subscriptionDuration: SubscriptionDuration? = nil) {
				self.rawValue = rawValue
				self.kind = kind
				self.isPrepurchased = isPrepurchased
				self.subscriptionDuration = subscriptionDuration
			}
		}
		
		public init?(product: SKProduct?, id localID: ID? = nil, info: [String: Any]? = nil) {
			guard let id = localID ?? Capitalist.instance.productID(from: product?.productIdentifier) else {
				self.id = .none
				return nil
			}
			self.info = info
			self.id = id
			self.product = product
		}
		
		public var introductoryPrice: String? {
			if #available(iOS 11.2, OSX 10.13.2, *) {
				guard let price = product?.introductoryPrice?.price as? Double else { return nil }
				return String(format: "$%.02f", price)
			} else {
				return nil
			}
		}
		
		@available(OSX 10.13.2, iOS 11.2, *)
		public var freeTrialDays: Int? {
			guard let intro = self.product?.introductoryPrice, intro.paymentMode == .freeTrial else { return nil }
			
			let count = intro.subscriptionPeriod.numberOfUnits
			switch intro.subscriptionPeriod.unit {
			case .day: return count
			case .week: return count * 7
			case .month: return count * 30
			case .year: return count * 365
			default: return nil
			}
		}

		@available(OSX 10.13.2, iOS 11.2, *)
		public var freeTrialDurationDescription: String? {
			guard let intro = self.product?.introductoryPrice, intro.paymentMode == .freeTrial else { return nil }
			
			let count = intro.subscriptionPeriod.numberOfUnits
			switch intro.subscriptionPeriod.unit {
			case .day: return count == 1 ? NSLocalizedString("1 day", comment: "1 day trial") : String(format: NSLocalizedString("%d days", comment: "Trial duration in days"), count)
			case .week: return count == 1 ? NSLocalizedString("1 day", comment: "1 day trial") :  String(format: NSLocalizedString("%d weeks", comment: "Trial duration in weeks"), count)
			case .month: return count == 1 ? NSLocalizedString("1 day", comment: "1 day trial") :  String(format: NSLocalizedString("%d months", comment: "Trial duration in months"), count)
			case .year: return count == 1 ? NSLocalizedString("1 day", comment: "1 day trial") :  String(format: NSLocalizedString("%d years", comment: "Trial duration in years"), count)
			default: return nil
			}
		}

		public var description: String {
			var text = self.id.rawValue + " - " + self.id.kind.rawValue
			if let reason = self.expirationReason { text += ", Expired: \(reason)" }
			if #available(iOS 11.2, OSX 10.13.2, *) {
				if !self.hasUsedTrial, self.product?.introductoryPrice != nil { text += " can trial" }
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
		
		var info: [String: Any]?
		public let id: Capitalist.Product.ID
		public var product: SKProduct?
		var recentPurchaseDate: Date? { didSet { updateSubscriptionInfo() }}
		var onDeviceExpirationDate: Date?
		
		static let currencyFormatter: NumberFormatter = {
			let formatter = NumberFormatter()
			formatter.numberStyle = .currency
			return formatter
		}()
		
		mutating func updateSubscriptionInfo() {
			if let date = recentPurchaseDate, let expiration = self.id.subscriptionDuration?.expiration(startingAt: date) {
				self.onDeviceExpirationDate = expiration
			}
		}
		
		public var expirationReason: ExpirationReason? {
			guard let reason = self.info?["expiration_intent"] as? Int else { return nil }
			return ExpirationReason(rawValue: reason)
		}
		
		public var title: String? { self.product?.localizedTitle }
		public var rawPrice: Double? { return self.product?.price.doubleValue }
		public var price: NSDecimalNumber? { return self.product?.price }
		public var localizedPrice: String? {
			guard let product = self.product else { return nil }
			Self.currencyFormatter.locale = product.priceLocale
			return Self.currencyFormatter.string(from: product.price)
		}
		public var isInBillingRetryPeriod: Bool { return Bool(any: self.info?["is_in_billing_retry_period"]) }
		public var isInIntroOfferPeriod: Bool { return Bool(any: self.info?["is_in_intro_offer_period"]) }
		public var isInTrialPeriod: Bool { return Bool(any: self.info?["is_trial_period"]) }
		public var subscriptionCancellationDate: Date? {
			if let date = self.date(for: "cancellation_date") { return date }
			guard let recentPurchase = recentPurchaseDate, let duration = subscriptionDuration else { return nil }
			
			return recentPurchase.addingTimeInterval(duration)
		}
		public var subscriptionDuration: TimeInterval? {
			if #available(iOS 11.2, macOS 10.13.2, *) {
				guard id.kind == .subscription, let period = product?.subscriptionPeriod else { return nil }

				return TimeInterval(period.numberOfUnits) * period.unit.timeInterval
			} else {
				return nil
			}
		}
		public var subscriptionExpirationDate: Date? {
			guard let onDevice = onDeviceExpirationDate else { return self.date(for: "expires_date") }
			guard let receipt = self.date(for: "expires_date") else { return onDevice }
			
			return max(onDevice, receipt)
		}
		public var originalPurchaseDate: Date? { return self.date(for: "original_purchase_date") }
		public var purchaseDate: Date? { return self.date(for: "purchase_date") }
		public var hasUsedTrial: Bool { return self.isInTrialPeriod || self.isInIntroOfferPeriod || self.originalPurchaseDate != nil }
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
			switch self.id.kind {
			case .none: return false
			case .nonConsumable: return self.quantity > 0
			case .consumable: return false
			case .subscription: return self.subscriptionExpirationDate != nil
			case .notSet: return false
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
				Capitalist.instance.receipt.refresh() { error in completion(self.subscriptionState) }
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

@available(iOS 11.2, macOS 10.13.2, *)
extension SKProduct.PeriodUnit {
	var timeInterval: TimeInterval {
		switch self {
		case .day: return 1440 * 60
		case .week: return 7 * 1440 * 60
		case .month: return 31 * 1440 * 60
		case .year: return 365 * 1440 * 60
		default: return 0
		}
	}
}
