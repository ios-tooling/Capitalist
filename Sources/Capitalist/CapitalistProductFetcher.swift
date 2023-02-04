//
//  CapitalistProductFetcher.swift
//  
//
//  Created by Ben Gottlieb on 1/12/22.
//

import Foundation
import StoreKit


extension Capitalist {
	public class ProductFetcher: NSObject, SKProductsRequestDelegate {
		public typealias ProductCompletion = (Result<[Product], Error>) -> Void
		var completion: ProductCompletion?
		var request: SKProductsRequest!
		let useStoreKit2: Bool
		
		public init(ids: [Capitalist.Product.ID], useStoreKit2: Bool, completion: @escaping ProductCompletion) {
			self.useStoreKit2 = useStoreKit2
			super.init()
			self.fetch(ids: ids, completion: completion)
		}
		
		func fetch(ids: [Capitalist.Product.ID], completion: @escaping ProductCompletion) {
			if #available(iOS 15.0, macOS 12, *), useStoreKit2 {
				Task {
					do {
						let skProds = try await StoreKit.Product.products(for: ids.map { $0.rawValue })
						if skProds.isEmpty {
							print("😫 No products? Check https://developer.apple.com/library/archive/technotes/tn2413/_index.html")
						}
						let prods = skProds.compactMap { Product(product: $0) }
						Capitalist.instance.load(products: prods)
						completion(.success(prods))
					} catch {
						print("Failed to fetch products: \(error)")
						completion(.failure(error))
					}
				}
				return
			} else {
				self.completion = completion
				request = SKProductsRequest(productIdentifiers: Set(ids.map({ $0.rawValue })))
				request.delegate = self
				request.start()
			}
		}

		public func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
			Capitalist.instance.load(products: response.products)
			
			if response.products.isEmpty {
				print("😫 No products? Check https://developer.apple.com/library/archive/technotes/tn2413/_index.html")
			}

			completion?(.success(response.products.compactMap { Product(product: $0) }))
			request.delegate = nil
			completion = nil
		}
		
		public func request(_ request: SKRequest, didFailWithError error: Error) {
			completion?(.failure(error))
			request.delegate = nil
			completion = nil
		}
		
		public func requestDidFinish(_ request: SKRequest) {
			completion?(.success([]))
			request.delegate = nil
			completion = nil
		}
	}
}
