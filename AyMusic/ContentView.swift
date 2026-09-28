//
//  ContentView.swift
//  AyMusic
//
//  Created by Shiyukine on 8/10/25.
//

import SwiftUI

struct ContentView: View {
    @State private var showSecondWebView = false
    @State private var secondWebViewBaseUrl: String? = nil
    @State private var secondWebViewCloseUrl: String? = nil
    @State private var secondWebViewFilterByInclude: Bool = false
    
    var body: some View {
        NavigationStack {
            WebView.fromLocalFile(named: "index.html")
                .edgesIgnoringSafeArea(.all)
                .navigationDestination(isPresented: $showSecondWebView) {
                    SecondWebView(baseUrl: secondWebViewBaseUrl ?? "index.html", closeUrl: secondWebViewCloseUrl ?? "index.html", filterByInclude: secondWebViewFilterByInclude, onClose: {
                        showSecondWebView = false
                    })
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenSecondWebView"))) { notification in
                    let obj = notification.object as? [String: Any] 
                    secondWebViewBaseUrl = obj?["baseUrl"] as? String
                    secondWebViewCloseUrl = obj?["closeUrl"] as? String
                    secondWebViewFilterByInclude = obj?["filterByInclude"] as? Bool ?? false
                    showSecondWebView = true
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CloseSecondWebView"))) { _ in
                    showSecondWebView = false
                }
                .onAppear() {
                    AudioManager.shared.startSilentLoop()
                }
        }
    }
}

struct SecondWebView: View {
    let baseUrl: String
    let closeUrl: String
    let filterByInclude: Bool
    let onClose: () -> Void
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            ExtWebView.showWebView(baseUrl: baseUrl, closeUrl: closeUrl, filterByInclude: filterByInclude)
            
            // Close button
            // if ios >= 26
            if #available(iOS 26.0, *) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 30))
                        .padding(10)
                        .foregroundColor(.white)
                        .glassEffect()
                        .clipShape(Circle())
                        .padding()
                }
            } else {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 30))
                        .padding(10)
                        .foregroundColor(.white)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .padding()
                }
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}

#Preview {
    ContentView()
}
