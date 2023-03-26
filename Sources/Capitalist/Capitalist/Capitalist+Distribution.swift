//
//  File.swift
//  
//
//  Created by Ben Gottlieb on 12/9/22.
//

import StoreKit

extension Capitalist {
	public enum Distribution { case development, testflight, appStore }
	public enum ReceiptOverride { case production, sandbox
		var receiptName: String {
			switch self {
			case .production: return "receipt"
			case .sandbox: return "sandboxReceipt"
			}
		}
	}

	public static var distribution: Distribution {
		#if DEBUG
			return .development
		#else
			#if os(OSX)
				let bundlePath = Bundle.main.bundleURL
				let receiptURL = bundlePath.appendingPathComponent("Contents").appendingPathComponent("_MASReceipt").appendingPathComponent("receipt")
				
				return FileManager.default.fileExists(atPath: receiptURL.path) ? .appStore : .development
			#else
				#if targetEnvironment(simulator)
					return .development
				#endif
				if Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" && MobileProvisionFile.default?.properties["ProvisionedDevices"] == nil { return .testflight }
			
				return .appStore
			#endif
		#endif
	}
}


fileprivate class MobileProvisionFile {
	fileprivate convenience init?(url: URL?) { self.init(data: url == nil ? nil : try? Data(contentsOf: url!)) }
	
	fileprivate var properties: NSDictionary!
	
	fileprivate static var `default`: MobileProvisionFile? = MobileProvisionFile(url: Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"))
	fileprivate init?(data: Data?) {
		guard let data = data else { return nil }
		
		guard let file = String(data: data, encoding: .ascii) else { return nil }
		let scanner = Scanner(string: file)
		if scanner.scanStringUpTo(string: "<?xml version=\"1.0\" encoding=\"UTF-8\"?>") != nil, let contents = scanner.scanStringUpTo(string: "</plist>") {
			let raw = contents.appending("</plist>")
			self.properties = raw.propertyList() as? NSDictionary
		}
		
		if self.properties == nil { return nil }
	}
}


fileprivate extension Scanner {
	 func scanStringUpTo(string: String) -> String? {
		if #available(iOS 13.0, iOSApplicationExtension 13.0, watchOS 6.0, OSX 10.15, OSXApplicationExtension 10.15, *) {
				return self.scanString(string)
		  } else {
				var result: NSString?
				self.scanUpTo(string, into: &result)
				return result as String?
		  }
	 }
}

