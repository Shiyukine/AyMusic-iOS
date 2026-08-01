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
            WebViewTest.showWebView(baseUrl: "https://www.youtube.com/watch?v=J66gqneY518")
                .edgesIgnoringSafeArea(.all)
        }
    }
}

#Preview {
    ContentViewTest()
}
