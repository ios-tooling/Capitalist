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
	
	public enum CapitalistError: String, Error, LocalizedError, CustomStringConvertible {
		case productNotFound, purchaseAlreadyInProgress, requestTimedOut
		public var localizedDescription: String { return self.rawValue }
		public var description: String { return self.rawValue }
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
