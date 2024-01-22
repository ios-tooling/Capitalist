//
//  Products.swift
//  CapitalistTestApp
//
//  Created by Ben Gottlieb on 1/19/24.
//

import Foundation
import Capitalist

extension Capitalist.Product {
	
	static func loadProductIds() -> [Capitalist.Product.Identifier] {
		guard let path = Bundle.main.path(forResource: "Products", ofType: "plist"),
				let plist = FileManager.default.contents(atPath: path),
				let data = try? PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: String] else {
			return []
		}
		
		return data.map { key, value in
			Capitalist.Product.Identifier(rawValue: key, name: value)
		}
	}
	
}
