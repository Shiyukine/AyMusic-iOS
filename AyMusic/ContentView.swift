//
//  ContentView.swift
//  AyMusic
//
//  Created by Shiyukine on 8/10/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        // Option 1: Try loading from bundle (recommended)
        WebView.fromLocalFile(named: "index.html")
            .edgesIgnoringSafeArea(.all)
        
        // Option 2: If bundle resources don't work, use embedded HTML (uncomment below)
        /*
        WebView(htmlString: HTMLContent.exampleHTML)
            .edgesIgnoringSafeArea(.all)
        */
    }
}

#Preview {
    ContentView()
}
