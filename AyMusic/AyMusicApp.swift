//
//  AyMusicApp.swift
//  AyMusic
//
//  Created by Shiyukine on 8/10/25.
//

import SwiftUI
import SwiftData
import WebKit

@main
struct AyMusicApp: App {
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background {
                WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                    CookieFileStore.save(cookies)
                }
            }
        }
    }
}
