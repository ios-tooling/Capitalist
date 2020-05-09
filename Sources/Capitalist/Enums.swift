//
//  CapitalistManagerEnums.swift
//  
//
//  Created by ben on 5/5/20.
//

import Foundation

extension CapitalistManager {
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
