//
//  File.swift
//  
//
//  Created by Ben Gottlieb on 1/12/22.
//

import Foundation
import StoreKit


extension Capitalist {
	public class ProductFetcher: NSObject, SKProductsRequestDelegate {
		public typealias ProductCompletion = (Result<[SKProduct], Error>) -> Void
		var completion: ProductCompletion?
		var request: SKProductsRequest!
		
		public init(ids: [Capitalist.Product.ID], completion: @escaping ProductCompletion) {
			super.init()
			self.fetch(ids: ids, completion: completion)
		}
		
		func fetch(ids: [Capitalist.Product.ID], completion: @escaping ProductCompletion) {
			self.completion = completion
			request = SKProductsRequest(productIdentifiers: Set(ids.map({ $0.rawValue })))
			request.delegate = self
			request.start()
		}

		public func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
			Capitalist.instance.load(products: response.products)
			
			completion?(.success(response.products))
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
