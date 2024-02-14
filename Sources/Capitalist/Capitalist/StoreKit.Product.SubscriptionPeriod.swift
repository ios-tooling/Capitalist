//
//  File.swift
//  
//
//  Created by Ben Gottlieb on 2/14/24.
//

import StoreKit

extension StoreKit.Product.SubscriptionPeriod {
	var localizedDuration: String {
		"\(value) \(value == 1 ? unit.singular : unit.plural)"
	}
}

extension StoreKit.Product.SubscriptionPeriod.Unit {
	var singular: String {
		switch self {
		case .year: NSLocalizedString("year", comment: "year")
		case .month: NSLocalizedString("month", comment: "month")
		case .week: NSLocalizedString("week", comment: "week")
		default: NSLocalizedString("day", comment: "day")
		}
	}
	
	var plural: String {
		switch self {
		case .year: NSLocalizedString("years", comment: "years")
		case .month: NSLocalizedString("months", comment: "months")
		case .week: NSLocalizedString("weeks", comment: "weeks")
		default: NSLocalizedString("days", comment: "days")
		}
	}
}
