//
//  Receipt.Core.swift
//
//
//  Created by Ben Gottlieb on 2/11/24.
//

import Foundation

struct ReceiptCore: Codable {
	let environment: String
	let receipt: ReceiptData
	let status: Int
	
	struct ReceiptData: Codable {
		let bundle_id: String
		let application_version: String
		let original_application_version: String?
		let original_purchase_date: Date?
		let original_purchase_date_ms: String?
		let receipt_creation_date: Date?
		let receipt_type: String
	}
}
