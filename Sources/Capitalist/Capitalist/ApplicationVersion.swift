//
//  ApplicationVersion.swift
//
//
//  Created by Ben Gottlieb on 2/12/24.
//

import Foundation

public struct ApplicationVersion: Comparable, CustomStringConvertible, CustomDebugStringConvertible {
	var components: [Int] { versionComponents + buildComponents }
	var buildComponents: [Int]
	var versionComponents: [Int]
	
	public var description: String {
		var result = "v"
		
		if !versionComponents.isEmpty { result += versionComponents.map { String($0) }.joined(separator: ".") }
		if !buildComponents.isEmpty { result += " (" + buildComponents.map { String($0) }.joined(separator: ".") + ")" }
		return result
	}
	
	public var debugDescription: String {
		description
	}
	
	public static func ==(lhs: Self, rhs: Self) -> Bool {
		lhs.components == rhs.components
	}

	public static func <(lhs: Self, rhs: Self) -> Bool {
		let lComponents = lhs.components
		let rComponents = rhs.components
		
		for i in 0..<(max(lComponents.count, rComponents.count)) {
			let left = i < lComponents.count ? lComponents[i] : 0
			let right = i < rComponents.count ? rComponents[i] : 0
			
			if left < right { return true }
			if left > right { return false }
		}
		
		return false
	}

	public init?(_ string: String?) {
		guard let string else { return nil }
		versionComponents = string.intComponents
		buildComponents = []
	}
	
	public init?(_ bundle: Bundle = .main) {
		guard let info = bundle.infoDictionary, let version = info["CFBundleShortVersionString"] as? String, let build = info["CFBundleVersion"] as? String else { return nil }
		
		versionComponents = version.intComponents
		buildComponents = build.intComponents

	}
	
	public static let v1 = ApplicationVersion("1.0")!
}

fileprivate extension String {
	var intComponents: [Int] {
		components(separatedBy: ".").compactMap { Int($0) }
	}
}
