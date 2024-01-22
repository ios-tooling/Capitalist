//
//  ContentView.swift
//  CapitalistTestApp
//
//  Created by Ben Gottlieb on 1/19/24.
//

import SwiftUI
import Capitalist

struct ContentView: View {
	@ObservedObject var capitalist = Capitalist.instance
	
	 var body: some View {
		  VStack {
			  let products: [Capitalist.Product] = Array(capitalist.availableProducts.values)
			  
			  ForEach(products) { product in
						Button(action: {
							Task {
								do {
									try await capitalist.purchase(product)
									capitalist.objectWillChange.send()
								} catch {
									print("Purchase failed: \(error)")
								}
							}
						}) {
							ProductRow(product: product)
						}
				  }
		  }
		  .padding()
	 }
}

struct ProductRow: View {
	let product: Capitalist.Product
	@State var isPurchased = false
	
	var body: some View {
		HStack {
			Text(product.name ?? "--")
			if isPurchased {
				Image(systemName: "checkmark")
			}
		}
		.task {
			isPurchased = await product.hasPurchased
		}
	}
}

#Preview {
	 ContentView()
}
