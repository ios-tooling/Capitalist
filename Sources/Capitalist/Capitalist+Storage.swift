//
//  Capitalist+Storage.swift
//  
//
//  Created by Ben Gottlieb on 12/9/22.
//

import Foundation


extension Capitalist {
	struct PurchasedSubscriptions: Codable {
		var d: [String: Date] = [:]
	}
	
	func saveLocalExpirationDate(for product: Capitalist.Product) {
		var saved = PurchasedSubscriptions.load()
		saved.d[product.id.rawValue] = Date()
		saved.save()
	}
	
	func clearLocalExpirationDate(for product: Capitalist.Product) {
		var saved = PurchasedSubscriptions.load()
		saved.d.removeValue(forKey: product.id.rawValue)
		saved.save()
	}
	
	func clearAllExpirationDates() {
		PurchasedSubscriptions().save()
	}
}

extension Capitalist {
	func expiresAt(for product: Capitalist.Product) -> Date? {
		guard let date = PurchasedSubscriptions.load().d[product.id.rawValue] else { return nil }
		
		guard !date.isInFuture, let duration = product.product?.subscriptionPeriod else { return nil }
		let expires = duration.expiration(startingAt: date)
		let expiresFromNow = duration.expiration(startingAt: date)
		if expires.timeIntervalSinceReferenceDate > expiresFromNow.timeIntervalSinceReferenceDate { return nil }
		return expires
	}
}
extension Capitalist.PurchasedSubscriptions {
	static let defaultsKey = "c_sed"
	func save() {
		guard let data = try? JSONEncoder().encode(self) else { return }
		
		UserDefaults.standard.set(data, forKey: Self.defaultsKey)
	}
	
	static func load() -> Self {
		if !Capitalist.instance.storeExpirationDatesInDefaults { return .init() }
		if let data = UserDefaults.standard.data(forKey: Self.defaultsKey), let result = try? JSONDecoder().decode(Self.self, from: data) { return result }
		return .init()
	}
}
