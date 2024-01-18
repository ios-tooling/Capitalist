//
//  Capitalist.Receipt.swift
//

import Foundation
import StoreKit

public typealias CapitalistCallback = () -> Void
public typealias CapitalistErrorCallback = (Error?) -> Void

extension Capitalist {
	public struct ProductExpiration: CustomStringConvertible {
		public let id: Product.ID
		public let date: Date
		
		public var description: String {
			"\(id): \(date.description)"
		}
	}
	public func currentExpirationDateAndProduct(for productIDs: [Product.ID] = Capitalist.instance.availableProductIDs) -> ProductExpiration? {
		var result: ProductExpiration?
		
		for id in productIDs {
			guard let product = self.availableProducts[id], let date = product.subscriptionExpirationDate else { continue }

			if result == nil || result!.date < date { result = ProductExpiration(id: id, date: date) }
		}

		return result
	}

	public func currentExpirationDate(for productIDs: [Product.ID] = Capitalist.instance.availableProductIDs) -> Date? {
		if let date = currentExpirationDateAndProduct(for: productIDs)?.date { return date }
		
		for id in productIDs {
			guard let product = self[id] else { continue }
			
			if let date = expiresAt(for: product) { return date }
		}
		return nil
	}
	
	public func isInTrial(for productIDs: [Product.ID]) -> Bool {
		return self.availableProducts.values.filter({ productIDs.contains($0.id) && $0.isInTrialPeriod }).count > 0
	}
	
	public func hasUsedTrial(for productIDs: [Product.ID]) -> Bool {
		return self.availableProducts.values.filter({ productIDs.contains($0.id) && $0.hasUsedTrial }).count > 0
	}
	
	private func load(receipts: [[String: Any]], latest: [String: Any]?) {
		DispatchQueue.main.async {
			self.purchasedConsumables = []
			for receipt in receipts {
				guard
					let id = self.productID(from: receipt["product_id"] as? String ?? ""),
					let product = Capitalist.instance[id]
				else { continue }
				
				if self.availableProducts[id] == nil { self.availableProducts[id] = product }
				if product.id.kind == .consumable, let purchaseDate = receipt.purchaseDate {
					self.recordConsumablePurchase(of: product.id, at: purchaseDate)
				} else if product.isOlderThan(receipt: receipt) {
					self.availableProducts[id]?.info = receipt
					if self.availableProducts[id]?.id.kind != .consumable, self.availableProducts[id]?.hasPurchased == true, !self.purchasedProducts.contains(id) {
						self.purchasedProducts.append(id)
					}
				}
			}
			self.hasSales = receipts.count > 0
			Capitalist.instance.objectChanged()
		}
	}
	
	public class Receipt: CustomStringConvertible {
		public static var appSpecificSharedSecret: String!			//this should be found in AppStoreConnect
		public var isRefreshing = false
		public var isValidating = false
		public var cachedReciept: [String: Any]?
		var currentCheckingHash: Int?
		var shouldValidateWithServer = true
		var serverResponse: String?
		public var receiptDecodeFailed = false
		public var hasCheckedReceipt = false

		var refreshCompletions: [(Error?) -> Void] = []
		public var description: String {
			if let cached = cachedReciept { return cached.description }
			if let serverResponse = serverResponse { return serverResponse }
			return "No Cached Receipt"
		}
		
		init() {
			do {
				if let data = lastValidReceiptData, let receipt = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
					self.updateCachedReceipt(label: "Setup", receipt: receipt)
				}
			} catch {
				print("Problem decoding last receipt: \(error)")
				lastValidReceiptData = nil
			}
		}
		
		public func refresh(completion: CapitalistErrorCallback? = nil) {
			if let comp = completion { self.refreshCompletions.append(comp) }
			
			if self.isRefreshing { return }
			if Capitalist.instance.loggingOn { print("Refreshing Receipt") }
			let op = SKReceiptRefreshRequest(receiptProperties: nil)
			self.isRefreshing = true

			op.delegate = self
			op.start()
		}
		
		func updateCachedReceipt(label: String, receipt: [String: Any]? = nil) {
			if receipt != nil { cachedReciept = receipt }
			if let actual = receipt ?? cachedReciept {
				let latest = (actual["latest_receipt_info"] as? [[String: Any]])?.first
				let all = actual["receipt"] as? [String: Any]
				if let inApp = all?["in_app"] as? [[String: Any]] { Capitalist.instance.load(receipts: inApp, latest: latest) }
				if let info = latest { Capitalist.instance.load(receipts: [info], latest: info) }
			}
			if Capitalist.instance.loggingOn { Capitalist.instance.logCurrentProducts(label: label) }
		}
		
		var receiptData: Data? {
			guard var url = Bundle.main.appStoreReceiptURL else { return nil }
			
			if let override = Capitalist.instance.receiptOverride {
				url = url.deletingLastPathComponent().appendingPathComponent(override.receiptName)
			}
			if let data = try? Data(contentsOf: url) { return data }
			if url.lastPathComponent == "receipt" {
				url = url.deletingLastPathComponent().appendingPathComponent("sandboxReceipt")
			} else {
				url = url.deletingLastPathComponent().appendingPathComponent("receipt")
			}
			return try? Data(contentsOf: url)
		}
		
		@discardableResult
		func loadBundleReceipt(completion: CapitalistErrorCallback? = nil) -> Bool {
			if !shouldValidateWithServer {
				completion?(nil)
				return false
			}
			if let receipt = receiptData {
				self.isValidating = true
				self.validate(data: receipt) {
					self.isValidating = false
					DispatchQueue.main.async {
                        NotificationCenter.default.post(name: Notifications.didRefreshReceipt, object: nil)
						completion?(nil)
					}
				}
				return true
			}
			hasCheckedReceipt = true
			if Capitalist.instance.loggingOn { print("No local receipt found") }
			completion?(nil)
			return false
		}

		var validationCompletions: [CapitalistCallback] = []
		
		func validate(data receiptData: Data, completion: @escaping CapitalistCallback) {
			self.validationCompletions.append(completion)

			let hash = receiptData.hashValue
			if self.currentCheckingHash == hash {
				self.callValidationCompletions()
				return
			}
			
			self.currentCheckingHash = hash
			let dict: [String: Any] = ["receipt-data": receiptData.base64EncodedString(options: []), "password": Receipt.appSpecificSharedSecret ?? "", "exclude-old-transactions": true]
			let useSandbox = Capitalist.instance.useSandbox
			let url = URL(string: "https://\(useSandbox ? "sandbox" : "buy").itunes.apple.com/verifyReceipt")!
			var request = URLRequest(url: url)
			request.httpBody = try! JSONSerialization.data(withJSONObject: dict, options: [])
			request.httpMethod = "POST"
			request.addValue("application/json", forHTTPHeaderField: "Content-Type")
			receiptDecodeFailed = false
			
			let task = URLSession.shared.dataTask(with: request) { result, response, error in
				Capitalist.instance.processingQueue.async {
					if let err = error { print("Error when validating receipt: \(err)") }
					if let data = result {
						self.serverResponse = String(data: data, encoding: .utf8)
						if let info = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any], let status = info["status"] as? Int {
							if (status == 21007 || (info["environment"] as? String) == "Sandbox"), !Capitalist.instance.useSandbox { // if the server sends back a 21007, we're in the Sandbox. Happens during AppReview
								Capitalist.instance.useSandbox = true
								self.currentCheckingHash = nil
								self.validate(data: receiptData, completion: completion)
								return
							} else if status == 21008 {
								Capitalist.instance.useSandbox = false
								self.currentCheckingHash = nil
								self.validate(data: receiptData, completion: completion)
								return
							} else if status == 21004 {
								print("Your secret \(Receipt.appSpecificSharedSecret == nil ? "is missing." : "doesn't seem to be correct.")")
								self.callValidationCompletions()
							} else if status == 21012 || status == 21002 || status == 21003 || status == 21005 {
								self.receiptDecodeFailed = true
							} else if status != 0 {
								print("Bad status (\(status)) returned from the AppStore.")
								self.callValidationCompletions()
							} else {
								self.receiptDecodeFailed = false
								Capitalist.instance.clearAllExpirationDates()
								self.lastValidReceiptData = data
								self.updateCachedReceipt(label: "Post Validation", receipt: info)
								self.callValidationCompletions()
							}
						}
					}
					DispatchQueue.main.async { self.callValidationCompletions() }
				}
			}
			
			task.resume()
		}
		
		func callValidationCompletions() {
			hasCheckedReceipt = true
			callRefreshCompletions(with: nil)
			let completions = self.validationCompletions
			self.currentCheckingHash = nil
			self.validationCompletions = []
			completions.forEach { $0() }
			(Capitalist.instance.delegate as? CapitalistReceiptDelegate)?.didDecodeReceipt()
		}
		
		var lastValidReceiptDataURL: URL {
			URL(fileURLWithPath: NSSearchPathForDirectoriesInDomains(.libraryDirectory, [.userDomainMask], true).first!).appendingPathComponent("cached_receipt.dat")
		}
		
		var lastValidReceiptData: Data? {
			set {
				if !Capitalist.instance.cacheDecryptedReceipts || newValue == nil {
					try? FileManager.default.removeItem(at: lastValidReceiptDataURL)
				} else {
					try? newValue?.write(to: lastValidReceiptDataURL)
				}
			}
			get { try? Data(contentsOf: lastValidReceiptDataURL) }
		}
	}
}

extension Bool {
	init(any: Any?) {
		if let bool = any as? Bool { self = bool }
		else if let str = any as? String, str == "true" { self = true }
		else { self = false }
	}
}


extension Int {
	init(any: Any?) {
		if let int = any as? Int { self = int }
		else if let str = any as? String, let int = Int(str) { self = int }
		else if let dbl = any as? Double { self = Int(dbl) }
		else { self = 0 }
	}
}


/* Sample Receipt:

{
  "environment" : "Production",
  "status" : 0,
  "latest_receipt" : "MIIT2gYJKoZIhvcNAQcCoIITyzCCE8cCAQExCzAJBgUrDgMCGgUAMIIDewYJKoZIhvcNAQcBoIIDbASCA2gxggNkMAsCAQ4CAQEEAwIBATALAgEZAgEBBAMCAQIwDAIBCgIBAQQEFgI0KzAMAgELAgEBBAQCAilsMA0CAQMCAQEEBQwDMi4yMA0CAQ0CAQEEBQIDAfvQMA0CARMCAQEEBQwDMS4wMA4CAQECAQEEBgIEVMloiTAOAgEJAgEBBAYCBFAyNTYwDgIBEAIBAQQGAgQx31F1MBACAQ8CAQEECAIGGnR6ejwxMBQCAQACAQEEDAwKUHJvZHVjdGlvbjAYAgEEAgECBBCjtOu56JK+MEibLU83/A7jMBwCAQUCAQEEFOaEsIbj4RWBPPzqjaVcSaTuLKrzMB0CAQICAQEEFQwTY29tLnN0YW5kYWxvbmUuYXJnbzAeAgEIAgEBBBYWFDIwMjAtMTAtMjlUMDA6NTU6NTBaMB4CAQwCAQEEFhYUMjAyMC0xMC0yOVQwMTowNzoxNVowHgIBEgIBAQQWFhQyMDE4LTA4LTEwVDE4OjA5OjU1WjA9AgEHAgEBBDVpNGigwmWz1gxJLokA+i0YM4ofpJbaROiiJcamTYfOjjnD+lbudqtqRmMtSXdzBRCrxYsYfDBEAgEGAgEBBDxjPgrg+x2UHltQRJGb/j0drTWYtj4G3NpvJOpmn7rS02Ab91Aj7oBTyQ8PF1AEZ2bS9Vg4zqHQ9aJGSZEwggFpAgERAgEBBIIBXzGCAVswCwICBqwCAQEEAhYAMAsCAgatAgEBBAIMADALAgIGsAIBAQQCFgAwCwICBrICAQEEAgwAMAsCAgazAgEBBAIMADALAgIGtAIBAQQCDAAwCwICBrUCAQEEAgwAMAsCAga2AgEBBAIMADAMAgIGpQIBAQQDAgEBMAwCAgarAgEBBAMCAQAwDAICBq8CAQEEAwIBADAMAgIGsQIBAQQDAgEAMA8CAgauAgEBBAYCBFTJaWkwGQICBqcCAQEEEAwOOTAwMDA2NTUwMzg2NTEwGQICBqkCAQEEEAwOOTAwMDA2NTUwMzg2NTEwHwICBqgCAQEEFhYUMjAxOS0xMS0xMFQxMjowOTowOVowHwICBqoCAQEEFhYUMjAxOS0xMS0xMFQxMjowOTowOVowMAICBqYCAQEEJwwlY29tLnN0YW5kYWxvbmUuYXJnby5jb2RhYmxlZ2VuZXJhdGlvbqCCDmUwggV8MIIEZKADAgECAggO61eH554JjTANBgkqhkiG9w0BAQUFADCBljELMAkGA1UEBhMCVVMxEzARBgNVBAoMCkFwcGxlIEluYy4xLDAqBgNVBAsMI0FwcGxlIFdvcmxkd2lkZSBEZXZlbG9wZXIgUmVsYXRpb25zMUQwQgYDVQQDDDtBcHBsZSBXb3JsZHdpZGUgRGV2ZWxvcGVyIFJlbGF0aW9ucyBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTAeFw0xNTExMTMwMjE1MDlaFw0yMzAyMDcyMTQ4NDdaMIGJMTcwNQYDVQQDDC5NYWMgQXBwIFN0b3JlIGFuZCBpVHVuZXMgU3RvcmUgUmVjZWlwdCBTaWduaW5nMSwwKgYDVQQLDCNBcHBsZSBXb3JsZHdpZGUgRGV2ZWxvcGVyIFJlbGF0aW9uczETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQClz4H9JaKBW9aH7SPaMxyO4iPApcQmyz3Gn+xKDVWG/6QC15fKOVRtfX+yVBidxCxScY5ke4LOibpJ1gjltIhxzz9bRi7GxB24A6lYogQ+IXjV27fQjhKNg0xbKmg3k8LyvR7E0qEMSlhSqxLj7d0fmBWQNS3CzBLKjUiB91h4VGvojDE2H0oGDEdU8zeQuLKSiX1fpIVK4cCc4Lqku4KXY/Qrk8H9Pm/KwfU8qY9SGsAlCnYO3v6Z/v/Ca/VbXqxzUUkIVonMQ5DMjoEC0KCXtlyxoWlph5AQaCYmObgdEHOwCl3Fc9DfdjvYLdmIHuPsB8/ijtDT+iZVge/iA0kjAgMBAAGjggHXMIIB0zA/BggrBgEFBQcBAQQzMDEwLwYIKwYBBQUHMAGGI2h0dHA6Ly9vY3NwLmFwcGxlLmNvbS9vY3NwMDMtd3dkcjA0MB0GA1UdDgQWBBSRpJz8xHa3n6CK9E31jzZd7SsEhTAMBgNVHRMBAf8EAjAAMB8GA1UdIwQYMBaAFIgnFwmpthhgi+zruvZHWcVSVKO3MIIBHgYDVR0gBIIBFTCCAREwggENBgoqhkiG92NkBQYBMIH+MIHDBggrBgEFBQcCAjCBtgyBs1JlbGlhbmNlIG9uIHRoaXMgY2VydGlmaWNhdGUgYnkgYW55IHBhcnR5IGFzc3VtZXMgYWNjZXB0YW5jZSBvZiB0aGUgdGhlbiBhcHBsaWNhYmxlIHN0YW5kYXJkIHRlcm1zIGFuZCBjb25kaXRpb25zIG9mIHVzZSwgY2VydGlmaWNhdGUgcG9saWN5IGFuZCBjZXJ0aWZpY2F0aW9uIHByYWN0aWNlIHN0YXRlbWVudHMuMDYGCCsGAQUFBwIBFipodHRwOi8vd3d3LmFwcGxlLmNvbS9jZXJ0aWZpY2F0ZWF1dGhvcml0eS8wDgYDVR0PAQH/BAQDAgeAMBAGCiqGSIb3Y2QGCwEEAgUAMA0GCSqGSIb3DQEBBQUAA4IBAQANphvTLj3jWysHbkKWbNPojEMwgl/gXNGNvr0PvRr8JZLbjIXDgFnf4+LXLgUUrA3btrj+/DUufMutF2uOfx/kd7mxZ5W0E16mGYZ2+FogledjjA9z/Ojtxh+umfhlSFyg4Cg6wBA3LbmgBDkfc7nIBf3y3n8aKipuKwH8oCBc2et9J6Yz+PWY4L5E27FMZ/xuCk/J4gao0pfzp45rUaJahHVl0RYEYuPBX/UIqc9o2ZIAycGMs/iNAGS6WGDAfK+PdcppuVsq1h1obphC9UynNxmbzDscehlD86Ntv0hgBgw2kivs3hi1EdotI9CO/KBpnBcbnoB7OUdFMGEvxxOoMIIEIjCCAwqgAwIBAgIIAd68xDltoBAwDQYJKoZIhvcNAQEFBQAwYjELMAkGA1UEBhMCVVMxEzARBgNVBAoTCkFwcGxlIEluYy4xJjAkBgNVBAsTHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MRYwFAYDVQQDEw1BcHBsZSBSb290IENBMB4XDTEzMDIwNzIxNDg0N1oXDTIzMDIwNzIxNDg0N1owgZYxCzAJBgNVBAYTAlVTMRMwEQYDVQQKDApBcHBsZSBJbmMuMSwwKgYDVQQLDCNBcHBsZSBXb3JsZHdpZGUgRGV2ZWxvcGVyIFJlbGF0aW9uczFEMEIGA1UEAww7QXBwbGUgV29ybGR3aWRlIERldmVsb3BlciBSZWxhdGlvbnMgQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDKOFSmy1aqyCQ5SOmM7uxfuH8mkbw0U3rOfGOAYXdkXqUHI7Y5/lAtFVZYcC1+xG7BSoU+L/DehBqhV8mvexj/avoVEkkVCBmsqtsqMu2WY2hSFT2Miuy/axiV4AOsAX2XBWfODoWVN2rtCbauZ81RZJ/GXNG8V25nNYB2NqSHgW44j9grFU57Jdhav06DwY3Sk9UacbVgnJ0zTlX5ElgMhrgWDcHld0WNUEi6Ky3klIXh6MSdxmilsKP8Z35wugJZS3dCkTm59c3hTO/AO0iMpuUhXf1qarunFjVg0uat80YpyejDi+l5wGphZxWy8P3laLxiX27Pmd3vG2P+kmWrAgMBAAGjgaYwgaMwHQYDVR0OBBYEFIgnFwmpthhgi+zruvZHWcVSVKO3MA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAUK9BpR5R2Cf70a40uQKb3R01/CF4wLgYDVR0fBCcwJTAjoCGgH4YdaHR0cDovL2NybC5hcHBsZS5jb20vcm9vdC5jcmwwDgYDVR0PAQH/BAQDAgGGMBAGCiqGSIb3Y2QGAgEEAgUAMA0GCSqGSIb3DQEBBQUAA4IBAQBPz+9Zviz1smwvj+4ThzLoBTWobot9yWkMudkXvHcs1Gfi/ZptOllc34MBvbKuKmFysa/Nw0Uwj6ODDc4dR7Txk4qjdJukw5hyhzs+r0ULklS5MruQGFNrCk4QttkdUGwhgAqJTleMa1s8Pab93vcNIx0LSiaHP7qRkkykGRIZbVf1eliHe2iK5IaMSuviSRSqpd1VAKmuu0swruGgsbwpgOYJd+W+NKIByn/c4grmO7i77LpilfMFY0GCzQ87HUyVpNur+cmV6U/kTecmmYHpvPm0KdIBembhLoz2IYrF+Hjhga6/05Cdqa3zr/04GpZnMBxRpVzscYqCtGwPDBUfMIIEuzCCA6OgAwIBAgIBAjANBgkqhkiG9w0BAQUFADBiMQswCQYDVQQGEwJVUzETMBEGA1UEChMKQXBwbGUgSW5jLjEmMCQGA1UECxMdQXBwbGUgQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkxFjAUBgNVBAMTDUFwcGxlIFJvb3QgQ0EwHhcNMDYwNDI1MjE0MDM2WhcNMzUwMjA5MjE0MDM2WjBiMQswCQYDVQQGEwJVUzETMBEGA1UEChMKQXBwbGUgSW5jLjEmMCQGA1UECxMdQXBwbGUgQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkxFjAUBgNVBAMTDUFwcGxlIFJvb3QgQ0EwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDkkakJH5HbHkdQ6wXtXnmELes2oldMVeyLGYne+Uts9QerIjAC6Bg++FAJ039BqJj50cpmnCRrEdCju+QbKsMflZ56DKRHi1vUFjczy8QPTc4UadHJGXL1XQ7Vf1+b8iUDulWPTV0N8WQ1IxVLFVkds5T39pyez1C6wVhQZ48ItCD3y6wsIG9wtj8BMIy3Q88PnT3zK0koGsj+zrW5DtleHNbLPbU6rfQPDgCSC7EhFi501TwN22IWq6NxkkdTVcGvL0Gz+PvjcM3mo0xFfh9Ma1CWQYnEdGILEINBhzOKgbEwWOxaBDKMaLOPHd5lc/9nXmW8Sdh2nzMUZaF3lMktAgMBAAGjggF6MIIBdjAOBgNVHQ8BAf8EBAMCAQYwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQUK9BpR5R2Cf70a40uQKb3R01/CF4wHwYDVR0jBBgwFoAUK9BpR5R2Cf70a40uQKb3R01/CF4wggERBgNVHSAEggEIMIIBBDCCAQAGCSqGSIb3Y2QFATCB8jAqBggrBgEFBQcCARYeaHR0cHM6Ly93d3cuYXBwbGUuY29tL2FwcGxlY2EvMIHDBggrBgEFBQcCAjCBthqBs1JlbGlhbmNlIG9uIHRoaXMgY2VydGlmaWNhdGUgYnkgYW55IHBhcnR5IGFzc3VtZXMgYWNjZXB0YW5jZSBvZiB0aGUgdGhlbiBhcHBsaWNhYmxlIHN0YW5kYXJkIHRlcm1zIGFuZCBjb25kaXRpb25zIG9mIHVzZSwgY2VydGlmaWNhdGUgcG9saWN5IGFuZCBjZXJ0aWZpY2F0aW9uIHByYWN0aWNlIHN0YXRlbWVudHMuMA0GCSqGSIb3DQEBBQUAA4IBAQBcNplMLXi37Yyb3PN3m/J20ncwT8EfhYOFG5k9RzfyqZtAjizUsZAS2L70c5vu0mQPy3lPNNiiPvl4/2vIB+x9OYOLUyDTOMSxv5pPCmv/K/xZpwUJfBdAVhEedNO3iyM7R6PVbyTi69G3cN8PReEnyvFteO3ntRcXqNx+IjXKJdXZD9Zr1KIkIxH3oayPc4FgxhtbCS+SsvhESPBgOJ4V9T0mZyCKM2r3DYLP3uujL/lTaltkwGMzd/c6ByxW69oPIQ7aunMZT7XZNn/Bh1XZp5m5MkL72NVxnn6hUrcbvZNCJBIqxw8dtk2cXmPIS4AXUKqK1drk/NAJBzewdXUhMYIByzCCAccCAQEwgaMwgZYxCzAJBgNVBAYTAlVTMRMwEQYDVQQKDApBcHBsZSBJbmMuMSwwKgYDVQQLDCNBcHBsZSBXb3JsZHdpZGUgRGV2ZWxvcGVyIFJlbGF0aW9uczFEMEIGA1UEAww7QXBwbGUgV29ybGR3aWRlIERldmVsb3BlciBSZWxhdGlvbnMgQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkCCA7rV4fnngmNMAkGBSsOAwIaBQAwDQYJKoZIhvcNAQEBBQAEggEAnOSCUjfPl6c1nHaC5yo1pBodcuHN7aBIIE496MLW2IoZuZIYeGP6RywlgXyRuwuiTRtEjAw5Q3JSxVeHl+JbI8t+I4O9Bbn7nr6SpIrjoPIdWaqnVXvG2lh9ALsFHGfo/mm/Nr80DJvhS0lQUU+xrJzvlMyRDhznBKkaSgXQE4m5f0APH9Py90hCkGj4ev5M/WDDME+zTQxywCMurKTP9472vV1U7I5AhtXMGM0MK7AFeL9NL82F9+ow6lQkdX+Q2CdA3nuutCeIp0TeNkqRg+4H9rAcCYjgadyJGzdTBn5X3CBRsPeyECA1Nb7VHkczTDvSM7bR+eXdfwq9ZbV5fA==",
  "latest_receipt_info" : [
	 {
		"product_id" : "com.standalone.argo.codablegeneration",
		"quantity" : "1",
		"transaction_id" : "90000655038651",
		"purchase_date_ms" : "1573387749000",
		"original_purchase_date_pst" : "2019-11-10 04:09:09 America/Los_Angeles",
		"purchase_date_pst" : "2019-11-10 04:09:09 America/Los_Angeles",
		"original_purchase_date_ms" : "1573387749000",
		"is_trial_period" : "false",
		"original_purchase_date" : "2019-11-10 12:09:09 Etc/GMT",
		"original_transaction_id" : "90000655038651",
		"purchase_date" : "2019-11-10 12:09:09 Etc/GMT"
	 }
  ],
  "receipt" : {
	 "receipt_type" : "Production",
	 "app_item_id" : 1422485641,
	 "receipt_creation_date" : "2020-10-29 00:55:50 Etc/GMT",
	 "bundle_id" : "com.standalone.argo",
	 "original_purchase_date" : "2018-08-10 18:09:55 Etc/GMT",
	 "in_app" : [
		{
		  "product_id" : "com.standalone.argo.codablegeneration",
		  "quantity" : "1",
		  "transaction_id" : "90000655038651",
		  "purchase_date_ms" : "1573387749000",
		  "original_purchase_date_pst" : "2019-11-10 04:09:09 America/Los_Angeles",
		  "purchase_date_pst" : "2019-11-10 04:09:09 America/Los_Angeles",
		  "original_purchase_date_ms" : "1573387749000",
		  "is_trial_period" : "false",
		  "original_purchase_date" : "2019-11-10 12:09:09 Etc/GMT",
		  "original_transaction_id" : "90000655038651",
		  "purchase_date" : "2019-11-10 12:09:09 Etc/GMT"
		}
	 ],
	 "adam_id" : 1422485641,
	 "receipt_creation_date_pst" : "2020-10-28 17:55:50 America/Los_Angeles",
	 "request_date" : "2020-10-29 01:07:15 Etc/GMT",
	 "request_date_pst" : "2020-10-28 18:07:15 America/Los_Angeles",
	 "version_external_identifier" : 836718965,
	 "request_date_ms" : "1603933635532",
	 "original_purchase_date_pst" : "2018-08-10 11:09:55 America/Los_Angeles",
	 "application_version" : "2.2",
	 "original_purchase_date_ms" : "1533924595000",
	 "receipt_creation_date_ms" : "1603932950000",
	 "original_application_version" : "1.0",
	 "download_id" : 29087573359665
  }
}

*/
