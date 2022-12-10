//
//  StoreKit+Extensions.swift
//  
//
//  Created by Ben Gottlieb on 12/9/22.
//

import Foundation
import StoreKit

extension SKPaymentTransaction {
	var detailedDescription: String {
		var text = "\(self.payment.productIdentifier) - \(self.transactionState.description)"
		
		if let date = self.transactionDate {
			text += " at \(date.description)"
		}
		
		return text
	}
}

extension SKPaymentTransactionState {
	var description: String {
		switch self {
		case .deferred: return "deferred"
		case .failed: return "failed"
		case .purchased: return "purchased"
		case .purchasing: return "purchasing"
		case .restored: return "restored"
		default: return "unknown state"
		}
	}
}

extension Error {
	public var isStoreKitCancellation: Bool {
		let err: Error? = self
		
		return (err as NSError?)?.code == 2 && (err as NSError?)?.domain == SKErrorDomain
	}
}


