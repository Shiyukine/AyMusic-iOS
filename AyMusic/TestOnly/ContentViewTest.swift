//
//  ContentViewTest.swift
//  AyMusic
//
//  Created by Shiyukine on 1/4/26.
//

import SwiftUI

struct ContentViewTest: View {
    
    var body: some View {
        NavigationStack {
            WebViewTest.showWebView(baseUrl: "https://soundcloud.com/signin")
                .edgesIgnoringSafeArea(.all)
        }
    }
}

#Preview {
    ContentViewTest()
}
