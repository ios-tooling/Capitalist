//
//  SwiftUIView.swift
//  
//
//  Created by Ben Gottlieb on 8/24/22.
//

#if canImport(SwiftUI)
#if canImport(Combine)
import SwiftUI
import Combine

#if os(iOS)
#if canImport(Suite)
	import Suite
#endif

@available(OSX 10.15, iOS 13.0, tvOS 13, watchOS 6, *)
public struct ReceiptView: View {
	public init() { }
	func copyReceipt() {
		UIPasteboard.general.string = Capitalist.instance.receipt.description
	}
	
	public var body: some View {
		ZStack() {
			Color(UIColor.systemBackground)
				.edgesIgnoringSafeArea(.all)
			ScrollView() {
				VStack() {
					Text(Capitalist.instance.receipt.description)
						.multilineTextAlignment(.leading)
						.font(.custom("Courier", size: 14))
						.onTapGesture {
							copyReceipt()
						}
					
					#if canImport(Suite)
					if let url = Bundle.main.appStoreReceiptURL {
						Button("Share Receipt") {
							UIApplication.shared.currentWindow?.rootViewController?.presentedest.share(something: [url], position: .topRight)
						}
						.padding()
					}
					#endif
				}
			}
		}
		.navigationTitle("Reciept")
	}
}

struct ReceiptView_Previews: PreviewProvider {
	static var previews: some View {
		ReceiptView()
	}
}

#endif
#endif
#endif
