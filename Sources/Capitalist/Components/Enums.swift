//
//  CapitalistEnums.swift
//  
//
//  Created by ben on 5/5/20.
//

import Foundation

extension Capitalist {
	public struct PurchaseFlag : OptionSet, Equatable {
		public static func ==(lhs: PurchaseFlag, rhs: PurchaseFlag) -> Bool {
			return lhs.rawValue == rhs.rawValue
		}

		public var rawValue: UInt
		
		public init(rawValue: UInt) {
			self.rawValue = rawValue
		}
		
		public static let prepurchased = PurchaseFlag(rawValue: 1 << 0)
		public static let restored = PurchaseFlag(rawValue: 1 << 1)
	}
	
	public enum CapitalistError: Error, LocalizedError, CustomStringConvertible {
		case productNotFound, storeKitProductNotFound, storeKit2ProductNotFound, cancelled, purchaseAlreadyInProgress, requestTimedOut, purchasePending, unverified, unknownStoreKitError, missingSecret, incorrectSecret, badServerStatus(Int)
		
		public var localizedDescription: String {
			switch self {
			case .productNotFound: "Product not found"
			case .storeKitProductNotFound: "StoreKit Product not found"
			case .storeKit2ProductNotFound: "StoreKit 2 Product not found"
			case .cancelled: "cancelled"
			case .purchaseAlreadyInProgress: "Purchase in progress"
			case .requestTimedOut: "Timed out"
			case .purchasePending: "Purchase pending"
			case .unverified: "Unverified"
			case .unknownStoreKitError: "Unknown StoreKit error"
			case .missingSecret: "Missing secret"
			case .incorrectSecret: "Incorrect secret"
			case .badServerStatus(let code): "Server response: \(code)"
			}
			
		}
		public var description: String { localizedDescription }
	}
	
	public enum ProductPurchsePhase: Equatable { case idle, purchasing, purchased, prepurchased }
	
	public enum State: Equatable { case idle, fetchingProducts, purchasing(Product), restoring
		public static func ==(lhs: State, rhs: State) -> Bool {
			switch (lhs, rhs) {
			case (.idle, .idle): return true
			case (.fetchingProducts, .fetchingProducts): return true
			case (.purchasing(let lhProd), .purchasing(let rhProd)): return lhProd == rhProd
			default: return false
			}
		}
	}
}

extension Notification {
	public static let purchaseFlagsKey = "Capitalist:PurchaseFlags"
	public var purchaseFlags: Capitalist.PurchaseFlag {
		return self.userInfo?[Notification.purchaseFlagsKey] as? Capitalist.PurchaseFlag ?? []
	}
	public static func purchaseFlagsDict(_ flags: Capitalist.PurchaseFlag) -> [String: Any] {
		return [Notification.purchaseFlagsKey: flags]
	}
}
