//
//  CapitalistTestAppApp.swift
//  CapitalistTestApp
//
//  Created by Ben Gottlieb on 1/19/24.
//

import SwiftUI
import Capitalist

@main
struct CapitalistTestAppApp: App {
	init() {
		let ids = Capitalist.Product.loadProductIds()
		Capitalist.instance.setup(productIDs: ids)
	}
	
	var body: some Scene {
		WindowGroup {
			ContentView()
		}
	}
}
