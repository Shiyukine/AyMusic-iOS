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
            WebViewTest.showWebView(baseUrl: "https://www.deezer.com/en/playlist/2186382862")
                .edgesIgnoringSafeArea(.all)
        }
    }
}

#Preview {
    ContentViewTest()
}
