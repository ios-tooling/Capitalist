//
//  ReceiptFetcher.swift
//  
//
//  Created by Ben Gottlieb on 3/26/23.
//

import Foundation

public struct ReceiptFetcher {
	public enum Kind { case current, production, sandbox, prodThenSandbox, sandboxThenProd }
	
	enum ReceiptError: Error { case noReceiptData, unableToDecode }
	
	public init() { }
	public func fetchReceipt(for kind: Kind = .current, secret: String? = nil) async throws -> [String: Any] {
		var currentKind = kind
		while true {
			guard let data = data(for: currentKind) else {
				guard let next = currentKind.next else { throw  ReceiptError.noReceiptData }
				currentKind = next
				continue
			}
			
			do {
				return try await decodeReceipt(data: data, kind: currentKind, secret: secret)
			} catch {
				guard let next = currentKind.next else { throw error }
				currentKind = next
			}
		}
	}
	
	public func decodeReceipt(data receiptData: Data, kind: Kind = .current, secret: String? = nil) async throws -> [String: Any] {
		
		var dict: [String: Any] = [
			"receipt-data": receiptData.base64EncodedString(options: []),
			"exclude-old-transactions": true
		]
		
		if let secret { dict["secret"] = secret }
		var isFirstRun = true
		
		while true {
			let url = isFirstRun ? kind.remoteURL : kind.alternate.remoteURL
			print("Checking \(url)")
			var request = URLRequest(url: url)
			request.httpBody = try! JSONSerialization.data(withJSONObject: dict, options: [])
			request.httpMethod = "POST"
			request.addValue("application/json", forHTTPHeaderField: "Content-Type")
			
			let (data, _) = try await URLSession.shared.data(for: request)
			if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
				if let error = json["status"] as? Int, error != 0 {
					print("********** Failed to decode receipt \(kind): \(error) **********")
				} else {
					return json
				}
			}
			if isFirstRun {
				isFirstRun.toggle()
			} else {
				throw ReceiptError.unableToDecode
			}
		}
	}
	
	public func data(for kind: Kind = .current) -> Data? {
		guard let url = kind.localURL else { return nil }
		return try? Data(contentsOf: url)
	}
}

extension ReceiptFetcher.Kind {
	var remoteURL: URL {
		if isProduction { return URL(string: "https://buy.itunes.apple.com/verifyReceipt")! }
		return URL(string: "https://sandbox.itunes.apple.com/verifyReceipt")!
	}

	var alternate: Self {
		if isProduction { return .sandbox }
		return .production
	}

	var isProduction: Bool {
		switch self {
		case .current:
			guard let url = Bundle.main.appStoreReceiptURL else { return false }
			return FileManager.default.fileExists(atPath: url.path)
		case .sandbox, .sandboxThenProd: return false
		case .production, .prodThenSandbox: return true
		}
	}
	
	var localURL: URL? {
		switch self {
		case .current:
			return Bundle.main.appStoreReceiptURL
			
		case .production, .prodThenSandbox:
			return Bundle.main.appStoreReceiptURL?.deletingLastPathComponent().appendingPathComponent("receipt")
			
		case .sandbox, .sandboxThenProd:
			return Bundle.main.appStoreReceiptURL?.deletingLastPathComponent().appendingPathComponent("sandboxReceipt")
		}
	}
	
	var next: Self? {
		switch self {
		case .sandboxThenProd: return .production
		case .prodThenSandbox: return .sandbox
		default: return nil
		}
	}
}

